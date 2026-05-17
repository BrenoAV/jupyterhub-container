import os
import docker

# ── Data Persistence (Fix for docker compose down) ────────────────────────────
# Forces JupyterHub to save the database and cookies in the persistent volume
c.JupyterHub.db_url = 'sqlite:////srv/jupyterhub/data/jupyterhub.sqlite'
c.JupyterHub.cookie_secret_file = '/srv/jupyterhub/data/jupyterhub_cookie_secret'

# ── Authenticator ─────────────────────────────────────────────────────────────
c.JupyterHub.authenticator_class = 'nativeauthenticator.NativeAuthenticator'
c.Authenticator.admin_users = {"admin"}
c.Authenticator.allow_all = True
c.NativeAuthenticator.open_signup = False
c.NativeAuthenticator.allowed_failed_logins = 5
c.NativeAuthenticator.seconds_before_next_try = 1200

# ── Server Limits ─────────────────────────────────────────────────────────────
c.JupyterHub.active_server_limit = 5
c.JupyterHub.shutdown_on_logout = True

c.DockerSpawner.args = [
    "--ResourceUseDisplay.track_cpu_percent=True",
    "--ResourceUseDisplay.track_disk_usage=True"
]

# ── Resource & GPU Profiles --------------------------─────────────────────────
# Users choose their resources when they log in. 
# Limits and GPU allocations are handled here instead of globally.
c.DockerSpawner.profile_list = [
    {
        'display_name': '🛠️ CPU Only (Data Prep & Coding)',
        'description': '4 CPUs, 16GB RAM. Best for writing code and lightweight processing.',
        'default': True,
        'spawner_override': {
            'cpu_limit': 4.0,
            'mem_limit': '16G',
            'extra_host_config': {
                'device_requests': []
            },
            'environment': {'GPU_ENABLED': 'False'}
        }
    },
    {
        'display_name': '🚀 GPU 0 (1x A100)',
        'description': '4 CPUs, 32GB RAM. Locks you to the first A100 GPU.',
        'spawner_override': {
            'cpu_limit': 4.0,
            'mem_limit': '16G',
            'extra_host_config': {
                'device_requests': [
                    docker.types.DeviceRequest(device_ids=["0"], capabilities=[["gpu"]])
                ]
            },
            'environment': {
                'GPU_ENABLED': 'True', 
                'CUDA_VISIBLE_DEVICES': '0'
            }
        }
    },
    {
        'display_name': '🚀 GPU 1 (1x A100)',
        'description': '4 CPUs, 32GB RAM. Locks you to the second A100 GPU.',
        'spawner_override': {
            'cpu_limit': 4.0,
            'mem_limit': '16G',
            'extra_host_config': {
                'device_requests': [
                    docker.types.DeviceRequest(device_ids=["1"], capabilities=[["gpu"]])
                ]
            },
            # Note: CUDA_VISIBLE_DEVICES is '0' here too. When Docker maps a single 
            # specific GPU to a container, the container sees it internally as GPU 0.
            'environment': {
                'GPU_ENABLED': 'True', 
                'CUDA_VISIBLE_DEVICES': '0'
            } 
        }
    }
]

# ── PRE-SPAWN HOOK (Folder Creation Only) ─────────────────────────────────────
# Must be async — DockerSpawner requires it.
# GPU logic is removed from here because profile_list handles it now.
async def pre_spawn_hook(spawner):
    username = spawner.user.name
    host_path = f"/jupyterhub/data/{username}"

    if not os.path.exists(host_path):
        os.makedirs(host_path, mode=0o755, exist_ok=True)
        # UID 1000 = jovyan, GID 100 = users (standard Jupyter Docker stacks)
        os.chown(host_path, 1000, 100)

c.Spawner.pre_spawn_hook = pre_spawn_hook

# ── Idle Culling Configuration ────────────────────────────────────────────────
c.JupyterHub.services = [
    {
        "name": "idle-culler",
        "admin": True,
        "command": [
            "python3",
            "-m",
            "jupyterhub_idle_culler",
            "--timeout=3600",    # 1 hour (cut down since GPUs are high-demand)
            "--cull-every=60",   # check every 1 minute
            "--max-age=36000"    # 10 hours max absolute age
        ],
    }
]

# ── Spawner ───────────────────────────────────────────────────────────────────
c.JupyterHub.spawner_class = "dockerspawner.DockerSpawner"
c.DockerSpawner.image = "custom-tiny-base:latest"

# Prevent Docker from trying to pull local-only images from a registry
c.DockerSpawner.pull_policy = "never"

# ── Volumes ───────────────────────────────────────────────────────────────────
c.DockerSpawner.notebook_dir = "/home/jovyan"

# Capital Z = private SELinux label per container (correct for Rocky Linux user isolation)
c.DockerSpawner.volumes = {
    "/jupyterhub/data/{username}": {"bind": "/home/jovyan", "mode": "rw,Z"}
}

# ── Networking ────────────────────────────────────────────────────────────────
c.DockerSpawner.network_name = os.environ.get("DOCKER_NETWORK_NAME", "jupyterhub_network")
c.DockerSpawner.use_internal_ip = True
c.JupyterHub.hub_ip = "0.0.0.0"
c.JupyterHub.hub_connect_ip = "jupyterhub"

# ── Timeouts & Cleanup ────────────────────────────────────────────────────────
c.DockerSpawner.remove = True  # auto-remove stopped containers
c.Spawner.default_url = "/lab"
c.Spawner.http_timeout = 120
c.Spawner.start_timeout = 300
