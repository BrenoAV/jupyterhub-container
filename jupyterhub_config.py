import os
import docker

# ── Data Persistence ──────────────────────────────────────────────────────────
c.JupyterHub.db_url = 'sqlite:////srv/jupyterhub/data/jupyterhub.sqlite'
c.JupyterHub.cookie_secret_file = '/srv/jupyterhub/data/jupyterhub_cookie_secret'

# --- Certificate --------------------------------------------------------------
# c.JupyterHub.ssl_key = '/path/to/my.key'
# c.JupyterHub.ssl_cert = '/path/to/my.cert'

# ── Authenticator ─────────────────────────────────────────────────────────────
c.JupyterHub.authenticator_class = 'nativeauthenticator.NativeAuthenticator'
c.Authenticator.admin_users = {"admin"}
c.Authenticator.allow_all = True
c.NativeAuthenticator.open_signup = False
c.NativeAuthenticator.allowed_failed_logins = 5
c.NativeAuthenticator.seconds_before_next_try = 1200
c.NativeAuthenticator.check_common_password = True
c.NativeAuthenticator.minimum_password_length = 8

# ── Server Limits ─────────────────────────────────────────────────────────────
c.JupyterHub.active_server_limit = 5
c.JupyterHub.shutdown_on_logout = True

c.DockerSpawner.args = [
    "--ResourceUseDisplay.track_cpu_percent=True",
    "--ResourceUseDisplay.track_disk_usage=True"
]

# ── Spawner ───────────────────────────────────────────────────────────────────
c.JupyterHub.spawner_class = "dockerspawner.DockerSpawner"
c.DockerSpawner.image = "custom-base:latest"  # Default fallback
c.DockerSpawner.pull_policy = "never"

# ── Profiles ──────────────────────────────────────────────────────────────────
c.DockerSpawner.options_form = """
<style>
  .corisco-container {
    margin: 1rem 0 1.5rem;
    padding: 1.25rem;
    border-radius: 14px;
    border: 1px solid var(--jp-border-color2, #ddd);
    background: var(--jp-layout-color1, #ffffff);
    color: var(--jp-ui-font-color1, #222);
  }

  .corisco-header {
    margin-bottom: 1rem;
  }

  .corisco-header h3 {
    margin: 0 0 .25rem;
    font-weight: 700;
    color: var(--jp-ui-font-color0, #1f2937);
  }

  .corisco-header p {
    margin: 0;
    color: var(--jp-ui-font-color2, #666);
    font-size: .95rem;
  }

  .corisco-info {
    margin: 1rem 0 1.25rem;
    padding: 1rem;
    border-radius: 10px;
    border: 1px solid var(--jp-border-color2, #e5e7eb);
    background: var(--jp-layout-color2, #f8fafc);
  }

  .profile-card {
    margin-bottom: .8rem;
    line-height: 1.45;
  }

  .profile-card strong {
    color: var(--jp-ui-font-color0, #111827);
  }

  .profile-card span {
    display: block;
    color: var(--jp-ui-font-color2, #555);
    font-size: .92rem;
    margin-top: .15rem;
  }

  .profile-group label {
    font-weight: 600;
    display: block;
    margin-bottom: .45rem;
    color: var(--jp-ui-font-color1, #222);
  }

  .profile-group select {
    background: var(--jp-layout-color1, #fff);
    color: var(--jp-ui-font-color1, #222);
    border: 1px solid var(--jp-border-color2, #ccc);
  }

  @media (prefers-color-scheme: dark) {
    .corisco-container {
      background: #111827;
      border-color: #374151;
      color: #f3f4f6;
    }

    .corisco-header h3,
    .profile-card strong,
    .profile-group label {
      color: #f9fafb;
    }

    .corisco-header p,
    .profile-card span {
      color: #d1d5db;
    }

    .corisco-info {
      background: #1f2937;
      border-color: #374151;
    }

    .profile-group select {
      background: #111827;
      color: #f9fafb;
      border-color: #4b5563;
    }
  }
</style>

<div class="corisco-container">
  <div class="corisco-header">
    <h3>Welcome to ✨ Corisco CoLab ✨</h3>
    <p>Choose the workspace that best fits what you want to run.</p>
  </div>

  <div class="corisco-info">
    <div class="profile-card">
      <strong>🔥 PyTorch with GPU</strong>
      <span>Best for deep learning, CUDA workloads, model training, and GPU experiments.</span>
      <span>Includes 8 CPUs, 64 GB RAM, and 1 dedicated GPU.</span>
    </div>

    <div class="profile-card">
      <strong>🛠️ CPU workspace</strong>
      <span>Best for notebooks, data analysis, teaching, scripting, and general development.</span>
      <span>Includes 32 CPUs and 64 GB RAM.</span>
    </div>
  </div>

  <div class="profile-group">
    <label for="profile">Workspace</label>
    <select name="profile" id="profile" class="form-control">
      <optgroup label="PyTorch with CUDA">
        <option value="torch_gpu0">🔥 [GPU 0] PyTorch</option>
        <option value="torch_gpu1">🔥 [GPU 1] PyTorch</option>
      </optgroup>
      <optgroup label="CPU only">
        <option value="cpu">🛠️ CPU workspace</option>
      </optgroup>
    </select>
  </div>
</div>
"""

def options_from_form(formdata):
    return {'profile': formdata.get('profile', ['cpu'])[0]}

c.DockerSpawner.options_from_form = options_from_form

# ── Pre-spawn hook: image + resources per profile ─────────────────────────────
async def pre_spawn_hook(spawner):
    username = spawner.user.name
    host_path = f"/jupyterhub/data/{username}"
    if not os.path.exists(host_path):
        os.makedirs(host_path, mode=0o755, exist_ok=True)
        os.chown(host_path, 1000, 100)  # jovyan:users

    profile = spawner.user_options.get('profile', 'cpu')

    def gpu_config(device_id):
        return {
            "device_requests": [
                docker.types.DeviceRequest(
                    device_ids=[str(device_id)],
                    capabilities=[["gpu", "compute", "utility"]]
                )
            ]
        }

    gpu_resources = dict(
        cpu_limit=8.0,
        cpu_guarantee=4.0,
        mem_limit='64G',
        mem_guarantee='32G',
    )

    if profile == 'torch_gpu0':
        spawner.image = "custom-torch:latest"
        spawner.extra_host_config = gpu_config(0)
        spawner.environment.update({
            "NVIDIA_VISIBLE_DEVICES": "0",
            "CUDA_VISIBLE_DEVICES": "0",
            "NVIDIA_DRIVER_CAPABILITIES": "compute,utility"
        })
        for k, v in gpu_resources.items(): setattr(spawner, k, v)

    elif profile == 'torch_gpu1':
        spawner.image = "custom-torch:latest"
        spawner.extra_host_config = gpu_config(1)
        spawner.environment.update({
            "NVIDIA_VISIBLE_DEVICES": "0",
            "CUDA_VISIBLE_DEVICES": "0",
            "NVIDIA_DRIVER_CAPABILITIES": "compute,utility"
        })
        for k, v in gpu_resources.items(): setattr(spawner, k, v)
        
    else:  # cpu
        spawner.image = "custom-base:latest"
        spawner.cpu_limit = 32.0
        spawner.cpu_guarantee = 16.0
        spawner.mem_limit = '64G'
        spawner.mem_guarantee = '32G'
        spawner.extra_host_config = {"device_requests": []}
        spawner.environment.update({
            "NVIDIA_VISIBLE_DEVICES": "none",
            "CUDA_VISIBLE_DEVICES": ""
        })

c.Spawner.pre_spawn_hook = pre_spawn_hook

# ── Idle Culling ──────────────────────────────────────────────────────────────
c.JupyterHub.services = [
    {
        "name": "idle-culler",
        "admin": True,
        "command": [
            "python3", "-m", "jupyterhub_idle_culler",
            "--timeout=1800",
            "--cull-every=60",
            "--max-age=36000"
        ],
    }
]

# ── Volumes ───────────────────────────────────────────────────────────────────
c.DockerSpawner.notebook_dir = "/home/jovyan"
c.DockerSpawner.volumes = {
    "/jupyterhub/data/{username}": {"bind": "/home/jovyan", "mode": "rw,Z"}
}

# ── Networking ────────────────────────────────────────────────────────────────
c.DockerSpawner.network_name = os.environ.get("DOCKER_NETWORK_NAME", "jupyterhub_network")
c.DockerSpawner.use_internal_ip = True
c.JupyterHub.hub_ip = "0.0.0.0"
c.JupyterHub.hub_connect_ip = "jupyterhub"

# ── Timeouts & Cleanup ────────────────────────────────────────────────────────
c.DockerSpawner.remove = True
c.Spawner.default_url = "/lab"
c.Spawner.http_timeout = 120
c.Spawner.start_timeout = 300
