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
    margin-bottom: 1.25rem;
  }

  .corisco-header h3 {
    margin: 0 0 .35rem;
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

  .profile-card:last-child {
    margin-bottom: 0;
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

  .profile-group {
    margin-bottom: 1.5rem;
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

  .welcome-tips {
    margin-top: 1.5rem;
    padding-top: 1.25rem;
    border-top: 1px solid var(--jp-border-color2, #e5e7eb);
    font-size: 0.9rem;
    color: var(--jp-ui-font-color2, #4b5563);
    line-height: 1.5;
  }

  .welcome-tips p {
    margin: 0 0 0.75rem 0;
  }

  .welcome-tips p:last-child {
    margin-bottom: 0;
  }

  .welcome-tips a {
    color: var(--jp-brand-color1, #2563eb);
    text-decoration: none;
    font-weight: 500;
  }

  .welcome-tips a:hover {
    text-decoration: underline;
  }

  .welcome-tips code {
    background: var(--jp-layout-color3, #e2e8f0);
    padding: 0.1rem 0.3rem;
    border-radius: 4px;
    font-size: 0.85rem;
    color: var(--jp-ui-font-color0, #0f172a);
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
    .profile-card span,
    .welcome-tips {
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

    .welcome-tips {
      border-top-color: #374151;
    }

    .welcome-tips a {
      color: #60a5fa;
    }

    .welcome-tips code {
      background: #374151;
      color: #f3f4f6;
    }
  }
</style>

<div class="corisco-container">
  <div class="corisco-header">
    <h3>Bem-vindo ao Corisco CoLab ⚡</h3>
    <p>Escolha a máquina ideal para iniciar a sua sessão.</p>
  </div>

  <div class="profile-group">
    <label for="profile">Selecione o ambiente</label>
    <select name="profile" id="profile" class="form-control">
      <optgroup label="Aceleração por Hardware (CUDA)">
        <option value="torch_gpu0">PyTorch (L40S - GPU 0)</option>
        <option value="torch_gpu1">PyTorch (L40S - GPU 1)</option>
      </optgroup>
      <optgroup label="Processamento Padrão">
        <option value="cpu">Ambiente CPU</option>
      </optgroup>
    </select>
  </div>

  <div class="corisco-info">
    <div class="profile-card">
      <strong>PyTorch com NVIDIA L40S</strong>
      <span>Focado em deep learning, processamento CUDA e treino de modelos. (8 CPUs, 64 GB RAM, 1x GPU L40S)</span>
    </div>
    <div class="profile-card">
      <strong>Ambiente CPU</strong>
      <span>Ótimo para análise de dados, scripts e desenvolvimento geral. (32 CPUs, 64 GB RAM)</span>
    </div>
  </div>

  <div class="welcome-tips">
    <p>💡 <strong>Dicas rápidas para o seu ambiente:</strong></p>
    <p>• <strong>Upload e Download:</strong> Você pode usar a interface gráfica do JupyterLab para arrastar e baixar arquivos soltos. Para pastas ou datasets pesados, compacte usando o comando <code>tar</code> no terminal antes de enviar ou fazer o download.</p>
    <p>• <strong>Controle de disco:</strong> Fique de olho no seu armazenamento. Use o comando <code>ncdu</code> no terminal para descobrir o tamanho das suas pastas e apague arquivos pesados que não usa mais.</p>
    <p>• <strong>Isole seus projetos:</strong> O ambiente é seu. Sinta-se à vontade para instalar e gerenciar dependências usando
       <a href="https://docs.conda.io/" target="_blank" rel="noopener">Conda</a>,
       <a href="https://docs.astral.sh/uv/" target="_blank" rel="noopener">uv</a> ou
       <a href="https://virtualenv.pypa.io/" target="_blank" rel="noopener">virtualenv</a>.
    </p>
    <p>• <strong>Sincronização:</strong> Use o Git pelo terminal ou pela interface do JupyterLab para gerenciar seu código fonte com repositórios externos.</p>
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

# ── Idle Culling (RBAC Approach) ──────────────────────────────────────────────
c.JupyterHub.services = [
    {
        "name": "idle-culler",
        "command": [
            "python3", "-m", "jupyterhub_idle_culler",
            "--timeout=1800",
            "--cull-every=60",
            "--max-age=43200"
        ],
    }
]

c.JupyterHub.load_roles = [
    {
        "name": "idle-culler",
        "description": "Culls idle servers",
        "scopes": [
            "list:users",          # Needed to iterate through users
            "read:users:activity", # Needed to check last activity timestamps
            "read:servers",        # Needed to inspect server statuses
            "delete:servers",      # Needed to actually shut down the notebooks
        ],
        "services": ["idle-culler"], # Assigns this role to the service defined above
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
