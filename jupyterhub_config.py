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
# c.NativeAuthenticator.check_common_password = True
# c.NativeAuthenticator.minimum_password_length = 10

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
  .profile-group { margin-bottom: 1rem; }
  .profile-group label { font-weight: 600; display: block; margin-bottom: .4rem; }
</style>

<div class="profile-group">
  <label for="profile">Select Server Profile:</label>
  <select name="profile" class="form-control">
    <optgroup label="── PyTorch + CUDA ──────────────────────────">
      <option value="torch_gpu0">🔥 PyTorch · GPU 0</option>
      <option value="torch_gpu1">🔥 PyTorch · GPU 1</option>
    </optgroup>
    <optgroup label="── CPU Only ─────────────────────────────────">
      <option value="cpu">🛠️ CPU Only</option>
    </optgroup>
  </select>
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
        cpu_guarantee=2.0,
        mem_limit='48G',
        mem_guarantee='16G',
    )

    if profile == 'torch_gpu0':
        spawner.image = "custom-torch:latest"
        spawner.extra_host_config = gpu_config(0)
        # ADDED: Map physical GPU 0 to logical GPU 0 inside the container
        spawner.environment.update({
            "NVIDIA_VISIBLE_DEVICES": "0",
            "CUDA_VISIBLE_DEVICES": "0"
        })
        for k, v in gpu_resources.items(): setattr(spawner, k, v)

    elif profile == 'torch_gpu1':
        spawner.image = "custom-torch:latest"
        spawner.extra_host_config = gpu_config(1)
        spawner.environment.update({
            "NVIDIA_VISIBLE_DEVICES": "1",
            "CUDA_VISIBLE_DEVICES": "0"
        })
        for k, v in gpu_resources.items(): setattr(spawner, k, v)
        
    else:  # cpu
        spawner.image = "custom-base:latest"
        spawner.cpu_limit = 16.0
        spawner.cpu_guarantee = 4.0
        spawner.mem_limit = '64G'
        spawner.mem_guarantee = '16G'
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
            "--timeout=3600",
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
