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
    <h3>Welcome to Corisco Lab ⚡</h3>
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
        <option value="torch_gpu0">🔥 PyTorch GPU 0</option>
        <option value="torch_gpu1">🔥 PyTorch GPU 1</option>
      </optgroup>
      <optgroup label="CPU only">
        <option value="cpu">🛠️ CPU workspace</option>
      </optgroup>
    </select>
  </div>
</div>
"""
