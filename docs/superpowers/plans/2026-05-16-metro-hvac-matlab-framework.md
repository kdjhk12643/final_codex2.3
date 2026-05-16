# Metro HVAC MATLAB Framework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a small-file MATLAB framework for the metro station HVAC graduation project.

**Architecture:** One `main.m` controls the whole workflow. One `config.m` centralizes all tunable parameters. Four step files map directly to the thesis task chain: data preparation, analysis and clustering, load prediction, and capacity optimization.

**Tech Stack:** MATLAB R2022b, Statistics and Machine Learning Toolbox, Deep Learning Toolbox, Global Optimization Toolbox.

---

### Task 1: Create MATLAB Project Skeleton

**Files:**
- Create: `main.m`
- Create: `config.m`
- Create: `step1_data_prepare.m`
- Create: `step2_analysis_cluster.m`
- Create: `step3_load_prediction.m`
- Create: `step4_capacity_optimization.m`

- [x] **Step 1: Create `config.m`**

Centralize data paths, preprocessing options, feature settings, LSTM/BP parameters, NSGA-II parameters, and device candidate capacities.

- [x] **Step 2: Create `main.m`**

Run the four thesis steps in order and save a summarized result file under `output/models`.

- [x] **Step 3: Create `step1_data_prepare.m`**

Read the CSV, parse timestamps, fill missing values, create time features, standardize continuous predictors, and return raw, clean, and modeling tables.

- [x] **Step 4: Create `step2_analysis_cluster.m`**

Run Pearson feature ranking, load-component ratio analysis, daily load-curve construction, K-Means clustering, and silhouette-based K selection.

- [x] **Step 5: Create `step3_load_prediction.m`**

Build a clear interface for LSTM and BP prediction. Include sequence construction, metric calculation, and fallback behavior when toolboxes are unavailable.

- [x] **Step 6: Create `step4_capacity_optimization.m`**

Build a clear interface for NSGA-II and TOPSIS. Include baseline comparison, objective definitions, constraints, and fallback grid-search behavior when `gamultiobj` is unavailable.

### Task 2: Verify Framework Files

**Files:**
- Check: all six `.m` files.

- [x] **Step 1: Confirm files exist**

Run: `Get-ChildItem *.m`

- [x] **Step 2: Confirm expected MATLAB function signatures exist**

Run a text scan for `function cfg = config`, `step1_data_prepare`, `step2_analysis_cluster`, `step3_load_prediction`, and `step4_capacity_optimization`.

- [x] **Step 3: Note runtime limitation**

MATLAB is not available in this shell, so full MATLAB execution must be run inside MATLAB R2022b.
