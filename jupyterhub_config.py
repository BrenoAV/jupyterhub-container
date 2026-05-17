import os
import docker

# ── Authenticator ─────────────────────────────────────────────────────────────
c.JupyterHub.authenticator_class = 'nativeauthenticator.NativeAuthenticator'
c.Authenticator.admin_users = {"admin"}
c.Authenticator.allow_all = True
c.NativeAuthenticator.open_signup = False
# c.NativeAuthenticator.check_common_password = True
# c.NativeAuthenticator.minimum_password_length = 10
c.NativeAuthenticator.allowed_failed_logins = 5
c.NativeAuthenticator.seconds_before_next_try = 1200

# ── Server & Resource Limits ──────────────────────────────────────────────────
# TODO: increase the possible memory usage
c.JupyterHub.active_server_limit = 5
c.JupyterHub.shutdown_on_logout = True

# TODO: increase the memory and cpu limits
c.DockerSpawner.mem_limit = "16G"
c.DockerSpawner.cpu_limit = 4.0

c.DockerSpawner.args = [
    "--ResourceUseDisplay.track_cpu_percent=True",
    "--ResourceUseDisplay.track_disk_usage=True"
]

# ── COMBINED PRE-SPAWN HOOK (GPU + Folder Creation) ───────────────────────────
# Must be async — DockerSpawner requires it to avoid silent failures
async def pre_spawn_hook(spawner):
    user_groups = [g.name for g in spawner.user.groups]
    new_host_config = {}

    if "gpu_users" in user_groups:
        new_host_config["device_requests"] = [
            docker.types.DeviceRequest(count=-1, capabilities=[["gpu"]])
        ]
        spawner.environment.update({"GPU_ENABLED": "True"})
    else:
        new_host_config["device_requests"] = []
        spawner.environment.update({"GPU_ENABLED": "False"})

    spawner.extra_host_config = new_host_config

    # 2. Folder Creation on the Host Partition
    # The Hub container must have /jupyterhub/data mounted (see docker-compose.yml)
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
            "--timeout=7200",    # 2 hours
            "--cull-every=120",  # check in 2m if changes
            "--max-age=36000" # 10 hours
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
# The host path lives inside the loopback-mounted /jupyterhub partition
c.DockerSpawner.volumes = {
    "/jupyterhub/data/{username}": {"bind": "/home/jovyan", "mode": "rw,Z"}
}

# ── Networking ────────────────────────────────────────────────────────────────
c.DockerSpawner.network_name = os.environ.get("DOCKER_NETWORK_NAME", "jupyterhub_network")
c.DockerSpawner.use_internal_ip = True
c.JupyterHub.hub_ip = "0.0.0.0"
c.JupyterHub.hub_connect_ip = "jupyterhub"

# ── Data Persistence ──────────────────────────────────────────────────────────
# Force JupyterHub to save its state inside the mounted Docker volume
c.JupyterHub.db_url = 'sqlite:////srv/jupyterhub/data/jupyterhub.sqlite'
c.JupyterHub.cookie_secret_file = '/srv/jupyterhub/data/jupyterhub_cookie_secret'

# ── Timeouts & Cleanup ────────────────────────────────────────────────────────
c.DockerSpawner.remove = True  # auto-remove stopped containers
c.Spawner.default_url = "/lab"
c.Spawner.http_timeout = 120
c.Spawner.start_timeout = 300
