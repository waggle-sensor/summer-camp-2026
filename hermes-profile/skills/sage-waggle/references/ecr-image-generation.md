# ECR Image Generation (Programmatic)

ECR requires two images per plugin:
- `ecr-icon.jpg` — 512×512 plugin icon
- `ecr-science-image.jpg` — 1920×1080 representative science image

## Approach: Pillow-based generation

Rather than sourcing stock images or using external tools, generate professional images programmatically with Python Pillow. This ensures consistency across plugins and makes regeneration trivial.

### Design principles (proven working)

1. **Distinct color identity per plugin** — each plugin gets a unique primary/secondary/accent/dark palette. Examples:
   - Object detection: navy/cyan/amber
   - Biology/taxonomy: forest green/emerald/lime
   - Neural/LLM: purple/violet/pink

2. **Visual motif per plugin** — a simple geometric symbol representing the plugin's function:
   - Bounding boxes with corner markers (object detection)
   - Leaf with veins + DNA helix (species classification)
   - Neural network layers with nodes and connections (LLM inference)

3. **Consistent layout** — all images share structure:
   - Icon (512×512): gradient background, grid overlay, centered motif, title + subtitle, SAGE/ECR badge
   - Science image (1920×1080): left panel (motif + title), right panel (specs card with Plugin Specifications, Architecture, Data Pipeline sections), NSF footer

4. **Pipeline visualization** — show the data flow as connected pill-shaped boxes: Camera → Inference → Publish → Beehive

### Implementation pattern

```python
from PIL import Image, ImageDraw, ImageFont

# Load system fonts (DejaVu Sans available on Ubuntu/Debian)
font_bold = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 48)
font_regular = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 24)
font_mono = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 22)

# Gradient fill helper
def draw_gradient_rect(draw, bbox, c1, c2, vertical=True):
    x1, y1, x2, y2 = bbox
    for y in range(y1, y2):
        t = (y - y1) / max(y2 - y1, 1)
        color = tuple(int(a + (b-a)*t) for a, b in zip(c1, c2))
        draw.line([(x1, y), (x2, y)], fill=color)
```

### Regeneration

The script at `scripts/generate_ecr_images.py` in the sage-edge-plugins repo generates all 6 images (3 plugins × 2 images). Run from repo root with the test venv:

```bash
source tests/.venv/bin/activate
python3 scripts/generate_ecr_images.py
```

Output: writes directly to each plugin's `ecr-meta/` directory.

### Quality checklist
- [ ] Icon readable at thumbnail size (64×64) — keep text large
- [ ] Science image has no trailing arrows or orphaned elements
- [ ] Pipeline shows full flow ending at "Beehive" (the cloud destination)
- [ ] NSF funding attribution in footer
- [ ] SAGE/ECR badge visible
- [ ] JPEG quality ≥ 95 for clean text rendering
- [ ] Use `random.seed(42)` for deterministic node placement in neural network motifs
