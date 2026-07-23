---
sidebar_label: EdgeRunner
sidebar_position: 4
---

import LabButtons from './components/LabButtons'

# EdgeRunner

<!-- <LabButtons id="ollama-hello-world-app" /> -->

## Introduction

Continuous environmental observation is fundamentally constrained by human capacity: no team of researchers can attend to every camera, at every site, at every hour of the day, and significant events can pass unnoticed in the gap between capture and inspection. AI-driven edge computing offers a means of overcoming this physical limitation by delegating persistent, around-the-clock observation to models running directly on the sensing hardware. EdgeRunner is our effort to make this capability broadly accessible. Building on our prior experiments with vision language models (VLMs) for environmental event and anomaly detection, we observed that the principal barrier to rapid deployment was not model capability but operational friction, each new scientific question required packaging, containerizing, and scheduling a dedicated plugin. EdgeRunner reduces this cycle from days to seconds by allowing a natural language prompt to serve directly as the deployed classifier.

![ImageOfPrompt](img/edgerunner/edgerunner-image.png)

## What is EdgeRunner?

EdgeRunner is a very experimental system that currently runs an app called ollama-hello-world on the Sage Nodes. At its core, the workflow is simple:

* Given an LLM model, a prompt, and a camera, EdgeRunner runs your prompt on the edge against an image captured from the specified camera.

* It supports a single tool call, upload_image, which the model can trigger on its own when the prompt calls for it. For example, a prompt like "Upload an image only if there's a cow in the scene" lets the model decide, per image, whether an upload is warranted.


Under the hood, the app is a lightweight agentic wrapper around an ([Ollama](https://ollama.com/)) client running on the node. On each scheduled run, it captures the latest frame from the selected camera and sends it to the chosen model together with the user's prompt. The model either answers directly or calls the upload_image tool, which queues the image for upload to the Sage data pipeline along with the model's reason for uploading. Each run also publishes performance metrics—token counts, model load and evaluation times, and tool call counts—so we can track the cost and latency of each model on edge hardware.

## How to run EdgeRunner

### Step 1
The prompt defines what the camera-connected model will do with each captured image. You can type your own or start from one of the suggested prompts:

* "Describe what you see in detail."
* "What objects are in the view?"
* "Is there anything unusual or dangerous?"
* "If there is a hummingbird present, upload a photo. Otherwise say 'no hummingbird found.'"

![ImageOfPrompt](img/edgerunner/prompt-image.png)

The last example demonstrates the tool-calling capability: the model only uploads an image when it believes the condition in the prompt has been met, turning a plain English sentence into an event-triggered data collection pipeline. And this prompt was used to make examples for this document. 

### Step 2

EdgeRunner lets you select which VLM will process your prompt. The current Sage-recommended models include gemma4 (e2b), gemma4 (e4b), qwen3-vl (2b), and qwen3-vl (4b). Smaller models load and respond faster on edge hardware, while larger models tend to be more accurate for complex queries.

![ImageOfModel](img/edgerunner/models-image.png)

### Step 3

Tasks can be configured to run at a fixed interval—every 1, 5, 10, 15, or 30 minutes, or every 1, 2, 4, or 8 hours. This turns a single question into a continuous monitoring task; the node will capture a new image and re-run your prompt at each interval.

![ImageOfModel](img/edgerunner/frequency-image.png)

### Step 4

Finally, choose the node you would like the task to run on (for example, node H00F) and one of the cameras attached to that node (for example, the Hummingbird Camera). Once submitted, the task appears in the Tasks panel where its status and outputs can be monitored.

![ImageOfModel](img/edgerunner/node-image.png) ![ImageOfModel](img/edgerunner/camera-image.png)

## Future Direction

EdgeRunner is already producing encouraging results. Running the prompt "If there is a hummingbird present, upload a photo. Otherwise say 'no hummingbird found.'" against the Hummingbird Camera, the system has successfully captured and uploaded genuine hummingbird visits with no additional engineering effort—a task that would previously have required a dedicated, finetuned detection model.

However, several reliability issues remain and define our next steps:
* False positive uploads. The model occasionally uploads photos when no hummingbird is present at all, including empty scenes. Reducing these spurious uploads is a priority, as they erode trust in the alerting pipeline and waste limited bandwidth on the nodes.

* Uncertainty about the model's decision process. When an upload does occur, it is currently difficult to tell why. Is the model confident it has positively identified a hummingbird, or is it simply reacting to the appearance of any object in the frame? We would like to surface the model's confidence and reasoning alongside each upload—for example, by requiring the model to justify detections, attaching calibrated confidence scores, or cross-checking detections with a second model—so that users can distinguish high-quality detections from lucky coincidences.

Addressing these issues will move EdgeRunner from an experimental convenience toward a dependable, self-serve monitoring tool: one where any scientist can point a sentence at a camera and trust what comes back.