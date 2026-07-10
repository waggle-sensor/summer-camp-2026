# ECR Plugin Examples — Real-World Reference

## giorgio808/yolov7-fire (LAVA-RAPID)

Source: https://github.com/LAVA-RAPID/yolov7-fire
ECR: https://portal.sagecontinuum.org/apps/app/giorgio808/yolov7-fire
Author: Giorgio Tran (LAVA-RAPID group)
ECR versions: 0.1.0 through 0.1.6+
Architectures: linux/amd64, linux/arm64

### Key Patterns Demonstrated

**1. Model weight baking via curl at build time:**
```dockerfile
FROM waggle/plugin-base:1.1.1-ml-torch1.9

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app

RUN pip3 install --upgrade pip
COPY requirements.txt /app/
RUN pip3 install --no-cache-dir --upgrade -r /app/requirements.txt

COPY test/ /app/test
COPY utils/ /app/utils
COPY models/ /app/models
COPY app.py /app/

# Download model weights at build time — baked into image layer
RUN curl -L -o /app/yolov7-fire.pt "<dropbox-url>"

ENTRYPOINT ["python3", "-u", "/app/app.py"]
```

Key takeaway: `curl -L -o /app/yolov7-fire.pt <url>` downloads the model at build time into a known path. No runtime download, no cache directory dependency.

**2. Split-file download for large models:**
The Dockerfile also shows (commented out) a pattern for splitting large models into parts for download reliability on constrained nodes:
```dockerfile
# RUN curl -L -o /app/yolov7_fire_aa "<part-1-url>"
# RUN curl -L -o /app/yolov7_fire_ab "<part-2-url>"
# ... (15 parts)
# RUN cat /app/yolov7_fire_* > /app/yolov7-fire.pt
```

**3. PyTorch model loading from explicit path:**
```python
self.model = Ensemble()
ckpt = torch.load(weightfile, map_location=self.device)
self.model.append(ckpt['ema' if ckpt.get('ema') else 'model'].float().fuse().eval())
```

**4. waggle/plugin-base for older PyTorch:**
Uses `waggle/plugin-base:1.1.1-ml-torch1.9` (includes PyTorch 1.9). For modern models (YOLO 8+, BioCLIP2, vLLM), use `nvcr.io/nvidia/pytorch:24.06-py3` instead.

**5. sage.yaml with multi-arch support:**
```yaml
name: "yolov7-fire"
version: "0.1.6"
description: "Finetuned YOLOV7 model for fire detection."
keywords: "fire-detection"
authors: "Giorgio Tran, Christopher Lee, Jason Leigh"
collaborators: "Laboratory for Advanced Visualization and Applications, Argonne National Laboratory"
funding: "RAPID Award NSF 2346568"
license: "MIT"
homepage: "https://github.com/LAVA-RAPID/yolov7-fire/tree/main"
source:
  architectures:
    - "linux/amd64"
    - "linux/arm64"
```

**6. ECR API metadata structure:**
```json
{
  "id": "giorgio808/yolov7-fire:0.1.0",
  "source": {
    "architectures": ["linux/amd64", "linux/arm64"],
    "branch": "main",
    "directory": ".",
    "dockerfile": "Dockerfile",
    "git_commit": "f98d9a5340f9821fc78b38970993f6b1bce7fb0d",
    "url": "https://github.com/LAVA-RAPID/yolov7-fire"
  },
  "thumbnail": "giorgio808/yolov7-fire/0.1.0/ecr-icon.jpg",
  "science_description": "giorgio808/yolov7-fire/0.1.0/ecr-science-description.md"
}
```

### ECR API for inspecting existing plugins

```bash
# Get all versions of a plugin
curl -sL 'https://ecr.sagecontinuum.org/api/apps/<namespace>/<name>'

# Response is {"data": [...]} with one entry per version
# Each entry has source.url (GitHub repo), source.git_commit, source.dockerfile
```

This is useful for finding real plugin source repos — the ECR entry's `source.url` field points to the GitHub repo that was built, and `homepage` often has an alternate link.

## Model Weight Hosting Options (from ECR examples)

| Method | Pros | Cons | Example |
|--------|------|------|---------|
| GitHub Releases | Stable URLs, versioned | 2GB file size limit | `ADD https://github.com/.../releases/download/v1/model.pt` |
| Dropbox (dl=1) | Easy upload, no size limit | URLs can break if sharing settings change | yolov7-fire uses this |
| LCRC / ANL hosting | Institutional, stable | Requires ANL account to upload | `https://web.lcrc.anl.gov/public/waggle/models/...` |
| HuggingFace Hub | Standard ML hosting, versioned, `huggingface-cli download` | Large models take time | Best for transformer models |
| ultralytics GitHub assets | Automatic for YOLO models | Cache path changes between versions | `https://github.com/ultralytics/assets/releases/download/v8.3.0/yolo11x.pt` |
