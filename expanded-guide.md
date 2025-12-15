# Nugget AE Tutorial Notes (Expanded Guide)

This document is a **tutorial-style companion** to the main README. Use it when you want more context, examples, and troubleshooting help.

It covers:
- What each AE step is doing (conceptually)
- Where outputs go and how to sanity-check them
- Practical tips for performance measurement and PAPI quirks
- How to detect supported CPU features for LLVM backends
- How PAPI event combinations are generated and why they’re needed

Architecture note: All scripts support selecting the target architecture via `-a/--architecture` (e.g., `x86_64`, `aarch64`). Where relevant, some scripts also distinguish the architecture used during sample selection via `--selection-architecture`.

> Recommended reading order:
> 1) Main README: follow the commands end-to-end once  
> 2) This doc: return here when you want deeper understanding or something breaks

---

## Table of contents

- [Nugget AE Tutorial Notes (Expanded Guide)](#nugget-ae-tutorial-notes-expanded-guide)
  - [Table of contents](#table-of-contents)
  - [0. Mental model of the pipeline](#0-mental-model-of-the-pipeline)
  - [1. Docker workflow tips](#1-docker-workflow-tips)
    - [1.1 Why Docker is recommended](#11-why-docker-is-recommended)
    - [1.2 Choosing `NUM_CORES_TO_USE`](#12-choosing-num_cores_to_use)
    - [1.3 Environment variables printed by `install.sh`](#13-environment-variables-printed-by-installsh)
  - [2. Step 1: Preparation and interval analysis](#2-step-1-preparation-and-interval-analysis)
    - [What to check after Step 1 succeeds](#what-to-check-after-step-1-succeeds)
  - [2.1 NPB](#21-npb)
  - [2.2 LSMS](#22-lsms)
  - [3. Step 2: Sample selection](#3-step-2-sample-selection)
    - [3.1 Why projection (PCA / random projections) exists](#31-why-projection-pca--random-projections-exists)
  - [3.2 NPB](#32-npb)
  - [3.3 LSMS](#33-lsms)
  - [4. Step 3: Nugget creation and validation](#4-step-3-nugget-creation-and-validation)
    - [4.1 NPB](#41-npb)
  - [4.2 LSMS and PAPI event combinations](#42-lsms-and-papi-event-combinations)
    - [Generate the cover file (simple command)](#generate-the-cover-file-simple-command)
    - [Run LSMS nugget validation](#run-lsms-nugget-validation)
  - [5. Measurement Notes](#5-measurement-notes)
    - [5.1 Measurement noise (important realism)](#51-measurement-noise-important-realism)
    - [5.2 What “good enough” looks like](#52-what-good-enough-looks-like)
  - [6. Common failure modes](#6-common-failure-modes)
    - [“Command not found” / wrong LLVM tools used](#command-not-found--wrong-llvm-tools-used)
    - [PCA step takes a very long time](#pca-step-takes-a-very-long-time)
    - [PAPI shows no available events](#papi-shows-no-available-events)
    - [Missing `libpfm.so.4`](#missing-libpfmso4)
  - [7. How to report issues (what info to include)](#7-how-to-report-issues-what-info-to-include)
  - [8. Advanced environment details](#8-advanced-environment-details)
    - [8.1 LLVM with Nugget passes](#81-llvm-with-nugget-passes)
    - [8.2 Detect supported CPU features](#82-detect-supported-cpu-features)
    - [8.3 PAPI install (hardware performance counters)](#83-papi-install-hardware-performance-counters)
    - [8.4 Test and generate PAPI event combinations](#84-test-and-generate-papi-event-combinations)
      - [If `libpfm.so.4` is missing](#if-libpfmso4-is-missing)
      - [Example output](#example-output)
      - [What `test_papi_combos` does](#what-test_papi_combos-does)
    - [8.5 gem5 `m5ops`](#85-gem5-m5ops)
    - [8.6 Sniper `sim_api`](#86-sniper-sim_api)

---

## 0. Mental model of the pipeline

Nugget AE is structured as a pipeline:

1) **Preparation + interval analysis**
   - Generate a base IR file and optimize it in the LLVM IR level
   - Builds analysis binaries
   - Runs them to produce IR basic-block vectors (BBVs) and interval/region data

2) **Sample selection**
   - K-means clustering
   - Random selection
   - Produces marker information that bounds the selected intervals in the execution

3) **Nugget creation + validation**
   - Builds “naive” (full program) and “nugget” (region-based) variants
   - Runs them and records measurements
   - Aggregates CSV outputs: runtimes and prediction errors

The best debugging strategy is to treat each step as producing an artifact that the next step consumes:
- Step 1 creates **analysis outputs**
- Step 2 consumes those outputs to create **selections + markers**
- Step 3 consumes selections + markers to create **nugget binaries + measurement CSVs**

If Step 3 fails, it is often because Step 2 didn’t produce what Step 3 expects.

---

## 1. Docker workflow tips

### 1.1 Why Docker is recommended
Docker gives you:
- Known compiler/LLVM/Python versions
- Fewer “works on my machine” issues
- A consistent filesystem layout

### 1.2 Choosing `NUM_CORES_TO_USE`
LLVM builds can be memory-heavy. If you see:
- the build getting killed, or
- random link failures under load,
reduce `NUM_CORES_TO_USE`.

A safe pattern is:
- start with something modest (e.g., 4–8)
- increase only if your machine has plenty of RAM

### 1.3 Environment variables printed by `install.sh`
`install.sh` prints `export ...` lines at the end.

Why this matters:
- Your shell needs to find the correct `clang/opt/llc`
- Your build system needs LLVM include/lib paths
- PAPI paths may also be set here

If a later script can’t find LLVM tools, it’s usually because these exports were not applied to the current shell.

---

## 2. Step 1: Preparation and interval analysis

This step builds and runs “analysis binaries” that record basic-block activity and produce vectors/CSV outputs.

### What to check after Step 1 succeeds
You should be able to find:
- `analysis-output.csv`
- `execution_time.txt`
- `stdout.log`, `stderr.log`

If those are missing, Step 2 will be operating on empty inputs.

---

## 2.1 NPB

What it does:
- Builds IR basic-block (BB) analysis binaries for the selected NPB benchmarks and size.
- Runs them to generate `analysis-output.csv` and `basic-block-info.txt` per benchmark.

By default, NPB runs:
- input class **A**
- **4 threads**

This is not “the final experimental setup”; it’s a fast pipeline sanity check.

Outputs land under (per benchmark and size):

```text
nugget-protocol-NPB/ae-experiments/analysis/threads-<T>/<architecture>/<benchmark>_<size>/
````

Example listing you might see:

```terminal
$ ls nugget-protocol-NPB/ae-experiments/analysis
threads-4

$ ls nugget-protocol-NPB/ae-experiments/analysis/threads-4/x86_64/bt_A
analysis-output.csv  basic-block-info.txt  execution_time.txt  stderr.log  stdout.log
```

Sanity check:

* `analysis-output.csv` exists and is non-empty
* `stderr.log` does not contain a crash traceback

Help (from `--help`):

```text
usage: preparation_and_interval_analysis.py [-h] [--project_dir PROJECT_DIR] [--size SIZE]
                                            [--num-threads NUM_THREADS] [--benchmarks BENCHMARKS ...]
                                            [--architecture ARCHITECTURE]

Build and run NPB IR BB analysis binaries.

options:
  -h, --help            show this help message and exit
  --project_dir -d      Path to project root containing nugget-protocol-NPB
  --size -s             The input class of NPB (default: A)
  --num-threads -t      The number of threads used for the experiments. (default: 4)
  --benchmarks -b       List of benchmarks to run. Defaults to all NPB benchmarks.
  --architecture -a     Target architecture for building the binaries. (Default: host architecture)
```

---

## 2.2 LSMS

What it does:
- Builds LSMS IR BB analysis binaries.
- Runs a single-process analysis to generate `analysis-output.csv` and `basic-block-info.txt` for the selected input.

LSMS is single-threaded.

Outputs are under:

```text
nugget-protocol-lsms/ae-experiments/analysis/<input-command>/<architecture>/
```

Sanity check:

* Look for the same “shape” of outputs as NPB (CSV/log/runtime text)
* Confirm the run didn’t silently exit early

Help (from `--help`):

```text
usage: preparation_and_interval_analysis.py [-h] [--project-dir PROJECT_DIR]
                                            [--input-directory INPUT_DIRECTORY]
                                            [--input-command INPUT_COMMAND]
                                            [--region-length REGION_LENGTH]
                                            [--architecture ARCHITECTURE]

Build and run LSMS IR BB analysis binaries.

options:
  -h, --help            show this help message and exit
  --project-dir -d      Path to project root containing nugget-protocol-NPB
  --input-directory -r  Relative path to input directory from project root. (default: 'ae-scripts/input')
  --input-command -c    Input command to run LSMS. (default: 'i_lsms')
  --region-length -l    Region length for basic block profiling. (default: 100000000)
  --architecture -a     Target architecture for the build (default: detected architecture)
```

---

## 3. Step 2: Sample selection

This step chooses representative intervals and generates markers.

### 3.1 Why projection (PCA / random projections) exists

BBVs can have very high dimensionality. Clustering directly can be slow or unstable.

Two common dimensionality reduction approaches:

* **PCA**: can be accurate but may be expensive for large BBVs
* **Random linear projections**: faster and often “good enough” for clustering

If you’re under time pressure, random projections are typically the pragmatic choice.

---

## 3.2 NPB

Typical command shape:

```bash
python3 ae-scripts/sample_selection.py \
  -d <PROJECT_DIR> \
  -s <INPUT_CLASS> \
  -b "CG EP" \
  -t <THREADS> \
  --k <NUM_CLUSTERS>
```

If PCA is slow, prefer:

```bash
python3 ae-scripts/sample_selection.py -d <PROJECT_DIR> --use-random-linear-projections
```

Expected output directories:

```text
# Sample selection (per benchmark-size)
nugget-protocol-NPB/ae-experiments/sample-selection/threads-<T>/<architecture>/k-means/<benchmark>_<size>/
nugget-protocol-NPB/ae-experiments/sample-selection/threads-<T>/<architecture>/random/<benchmark>_<size>/

# Marker input files (k-means + random combined)
nugget-protocol-NPB/ae-experiments/create-markers/threads-<T>/<grace-perc>/<architecture>/<benchmark>_<size>/input-files/
```

Sanity check:

* Marker files exist
* k-means and random selections exist
* Logs do not show errors

Help (from `--help`):

```text
usage: sample_selection.py [-h] --project_dir PROJECT_DIR [--size SIZE]
                           [--threads THREADS] [--num-regions NUM_REGIONS]
                           [--random-seed RANDOM_SEED] [--grace-perc GRACE_PERC]
                           [--region-length REGION_LENGTH]
                           [--num-warmup-region NUM_WARMUP_REGION]
                           [--benchmarks BENCHMARKS ...]
                           [--num-projections NUM_PROJECTIONS]
                           [--use-random-linear-projections]
                           [--architecture ARCHITECTURE]

Run sample selection and marker creation.

options:
  -h, --help            show this help message and exit
  --project_dir -d      Path to project root containing nugget-protocol-NPB (required)
  --size -s             Input class used for the analyses (default: A)
  --threads -t          Thread count used in the analysis runs (default: 4)
  --num-regions -n      Number of k nuggets for clustering (default: 30)
  --random-seed         Seed for random region selection (default: 627)
  --grace-perc          Grace percentage for marker creation (default: 0.98)
  --region-length       Region length for marker creation (default: 400000000)
  --num-warmup-region   Number of warmup regions for marker creation (default: 1)
  --benchmarks -b       List of NPB benchmarks to process (default: all)
  --num-projections -p  Number of projections for K-means clustering (default: 100)
  --use-random-linear-projections
                        Use random linear projections for K-means clustering
  --architecture -a     Target architecture for the analysis binaries (default: host)
```

---

## 3.3 LSMS

The step is analogous to NPB but uses LSMS paths/scripts.

Expected output directories:

```text
# K-means + random selection outputs for the chosen analysis dir
nugget-protocol-lsms/ae-experiments/sample-selection/k-means/<analysis-dir>/<architecture>/
nugget-protocol-lsms/ae-experiments/sample-selection/random/<analysis-dir>/<architecture>/

# Marker input files
nugget-protocol-lsms/ae-experiments/create-markers/<grace-perc>/<analysis-dir>/<architecture>/input-files/
```

Help (from `--help`):

```text
usage: sample_selection.py [-h] --project-dir PROJECT_DIR [--num-regions NUM_REGIONS]
                           [--random-seed RANDOM_SEED] [--grace-perc GRACE_PERC]
                           [--region-length REGION_LENGTH]
                           [--num-warmup-region NUM_WARMUP_REGION]
                           [--num-projections NUM_PROJECTIONS]
                           [--use-random-linear-projections]
                           [--analysis-dir ANALYSIS_DIR]
                           [--architecture ARCHITECTURE]

Run sample selection and marker creation.

options:
  -h, --help            show this help message and exit
  --project-dir -d      Path to project root containing nugget-protocol-lsms (required)
  --num-regions -n      Number of k nuggets for clustering (default: 30)
  --random-seed         Seed for random region selection (default: 627)
  --grace-perc          Grace percentage for marker creation (default: 0.98)
  --region-length       Region length for marker creation (default: 100000000)
  --num-warmup-region   Number of warmup regions for marker creation (default: 1)
  --num-projections -p  Number of projections for K-means clustering (default: 100)
  --use-random-linear-projections
                        Use random linear projections for K-means clustering
  --analysis-dir -r     Directory name under analysis results to use (default: i_lsms)
  --architecture -a     Architecture string used in binary names (default: host)
```

---

## 4. Step 3: Nugget creation and validation

This step:

* builds naive and nugget binaries
* runs them
* aggregates measurement and prediction CSVs

### 4.1 NPB

Minimal command:

```bash
python3 ae-scripts/nugget_creation_and_validaton.py \
  -d <PROJECT_DIR>
```

Outputs:

```text
nugget-protocol-NPB/ae-experiments/nugget-measurement/threads-<T>/<size>/<architecture>/measurements.csv
nugget-protocol-NPB/ae-experiments/nugget-measurement/threads-<T>/<size>/<architecture>/prediction-error.csv
```

Sanity check:

* `measurements.csv` has rows for naive and nugget runs
* `prediction-error.csv` is generated and non-empty

Help (from `--help`):

```text
usage: nugget_creation_and_validaton.py [-h] --project_dir PROJECT_DIR [--size SIZE]
                                        [--benchmarks BENCHMARKS] [--threads THREADS]
                                        [--grace-perc GRACE_PERC]
                                        [--architecture ARCHITECTURE]
                                        [--selection-architecture SELECTION_ARCHITECTURE]

Create and validate nuggets/naive binaries and measure runtime.

options:
  -h, --help            show this help message and exit
  --project_dir -d      Path to project root containing nugget-protocol-NPB (required)
  --size -s             Input size/class (e.g., A/B/C) (default: A)
  --benchmarks -b       Benchmarks to target, space/comma/semicolon separated (default: all)
  --threads -t          Number of threads for runs (default: 4)
  --grace-perc          Grace percentage used in markers (default: 0.98)
  --architecture -a     Target architecture for the analysis binaries (default: host)
  --selection-architecture
                        Architecture used during sample selection (default: host)
```

---

## 4.2 LSMS and PAPI event combinations

For LSMS, we need additional information: **PAPI event combinations**.

PAPI events are the hardware performance events we can measure on the machine. 
Not all machines expose the same set of PAPI events, and some machines may expose very few (or none) depending on CPU model, kernel configuration, and the PAPI/libpfm versions being used.

We provide an automated tool that helps extract a good set of event combinations from:

* all available PAPI events, and
* the available performance-counter registers

Please see [8.4 Test and generate PAPI event combinations](#84-test-and-generate-papi-event-combinations) for a detailed explanation of how the scripts work and how to interpret the output.

### Generate the cover file (simple command)

```bash
cd nugget_util/hook_helper/other_tools/papi
./test_papi_combos <EVENTS_PER_RUN> $PWD/<SYSTEM_ARCH>/bin/papi_avail <OUTPUT_FILE>
```

* If `<OUTPUT_FILE>` is omitted, the default output filename is `papi_combo_cover.txt`.
* If no cover is found, reduce `<EVENTS_PER_RUN>`. This means you will need more iterations (runs) to cover all supported events.

### Run LSMS nugget validation

After you have `papi_combo_cover.txt` (or a cover file in a custom location):

```bash
python3 ae-script/nugget_creation_and_validaton.py \
  -d <PROJECT_DIR> \
  -p <PATH_TO_PAPI_COVER_FILE>
```

Outputs:

```text
nugget-protocol-lsms/ae-experiments/nugget-measurement/<input-command>/<architecture>/measurements.csv
nugget-protocol-lsms/ae-experiments/nugget-measurement/<input-command>/<architecture>/prediction-error.csv
```

Help (from `--help`):

```text
usage: nugget_creation_and_validaton.py [-h] --project_dir PROJECT_DIR
                                        [--grace-perc GRACE_PERC]
                                        [--input-command INPUT_COMMAND]
                                        [--input-directory INPUT_DIRECTORY]
                                        --papi-combo-file-path PAPI_COMBO_FILE_PATH
                                        [--skip-build]
                                        [--architecture ARCHITECTURE]
                                        [--selection-architecture SELECTION_ARCHITECTURE]

Create and validate nuggets/naive binaries and measure runtime (LSMS + PAPI).

options:
  -h, --help            show this help message and exit
  --project_dir -d      Path to project root containing nugget-protocol-lsms (required)
  --grace-perc          Grace percentage used in markers (default: 0.98)
  --input-command -c    Input command to run LSMS (default: i_lsms)
  --input-directory -r  Relative path to input directory from project root (default: ae-scripts/input)
  --papi-combo-file-path -p
                        Path to papi event combination coverage file (required)
  --skip-build          Skip the build step if set
  --architecture -a     Target architecture for the build (default: host)
  --selection-architecture -s
                        Architecture used during sample selection (default: host)
```

---

## 5. Measurement Notes

### 5.1 Measurement noise (important realism)

Your reproduced runtimes may be noisier than the paper’s numbers. In our paper runs, we also used system-level controls (CPU frequency pinning, background-noise reduction, core pinning, etc.). These knobs are **not enforced** in the AE scripts because they are machine- and permission-dependent.

For portability, the AE scripts run **one measurement at a time**. In our paper experiments, we ran processes in parallel because we could cleanly isolate each process’s environment to maintain measurement accuracy and stability.

### 5.2 What “good enough” looks like

For AE purposes, it’s more important to reproduce the Nugget workflow and confirm that it behaves as described in the paper.
Exact numeric matches to the paper’s results can be difficult across machines, especially since the AE scripts do not fully isolate the measurement environment.

---

## 6. Common failure modes

### “Command not found” / wrong LLVM tools used

Symptoms:

* `clang` version mismatch
* `opt` can’t find passes

Fix:

* Ensure you applied the `export ...` lines printed by `install.sh` to your current shell.

### PCA step takes a very long time

Fix:

* Use `--use-random-linear-projections` for sample selection.

### PAPI shows no available events

Symptoms:

* `papi_avail` lists nothing useful

Fix:

* Try a different kernel/perf permission setup.
* Focus on runtime-only reproduction first (still valid for many AE goals).

### Missing `libpfm.so.4`

Fix:

* Install the provided `pfm` helper and set `LD_LIBRARY_PATH` as described in [8.4 Test and generate PAPI event combinations](#84-test-and-generate-papi-event-combinations).

---

## 7. How to report issues (what info to include)

When reporting a bug (GitHub issue or AE feedback), include:

* OS + kernel version
* CPU model
* Whether you used Docker or a host install
* The exact command that failed
* `stdout.log` / `stderr.log` from the failing step
* A directory listing of the expected output folder

This usually makes failures reproducible and quick to diagnose.

---

## 8. Advanced environment details

This section restores the detailed “how the environment works” notes (LLVM CPU features, PAPI installation, event combos, gem5 tools, etc.). 
If you are using Docker and the pipeline already runs, you can usually skim this section.

### 8.1 LLVM with Nugget passes

This builds LLVM with the Nugget analysis and transformation passes.

```bash
cd <PROJECT_DIR>/llvm-project
./build_cmd.sh <LLVM_INSTALL_PREFIX>
```

* Replace `<LLVM_INSTALL_PREFIX>` with the directory where you want LLVM installed.
* After this step, Nugget-enabled `clang`, `opt`, etc. reside under that install prefix (e.g., `<LLVM_INSTALL_PREFIX>/bin`).

---

### 8.2 Detect supported CPU features

Different machines support different feature sets in the LLVM backend. The following script discovers them automatically.

```bash
cd <PROJECT_DIR>/nugget_util/cmake/check-cpu-features
LLVM_BIN=<LLVM_INSTALL_PREFIX>/bin \
LLVM_LIB=<LLVM_INSTALL_PREFIX>/lib \
LLVM_INCLUDE=<LLVM_INSTALL_PREFIX>/include \
  make
./check-cpu-features
```

We separate `LLVM_BIN`, `LLVM_LIB`, and `LLVM_INCLUDE` because package-based LLVM distributions often split them across different directories, for example:

* `LLVM_BIN=/usr/bin`
* `LLVM_LIB=/usr/lib/llvm-19/lib`
* `LLVM_INCLUDE=/usr/include/llvm-19/llvm`

Example output in `llc-command.txt`:

```bash
$ cat llc-command.txt
-mcpu=neoverse-n1 -mtriple=aarch64-unknown-linux-gnu -mattr="+fp-armv8,+lse,+neon,+crc,+crypto"
```

You can pass this string to `llc` to enable appropriate backend optimizations.
The `cmake` files in the AE scripts automatically pull these information from the `llc-command.txt` if it exists.

---

### 8.3 PAPI install (hardware performance counters)

PAPI is used to collect hardware performance counters in Nugget runs.

```bash
cd <PROJECT_DIR>/nugget_util/hook_helper/other_tools/papi
./get-papi.sh
```

The tool will be installed under:

```text
<PROJECT_DIR>/nugget_util/hook_helper/other_tools/papi/<YOUR_SYSTEM_ARCH>
```

For example:

```text
<PROJECT_DIR>/nugget_util/hook_helper/other_tools/papi/aarch64
```

We refer to this directory as `<PAPI_PREFIX>`.

---

### 8.4 Test and generate PAPI event combinations

This step:

* Verifies that PAPI is correctly installed.
* Generates combinations of events so you can cover all supported events in a minimal number of runs, given a fixed number of hardware counters.

We recommend setting `<EVENTS_PER_RUN>` equal to the number of hardware counters on your machine.

You can get that by running:

```bash
<PAPI_PREFIX>/bin/papi_avail -a
```

Then:

```bash
cd <PROJECT_DIR>/nugget_util/hook_helper/other_tools/papi
./install-test-papi-combos.sh <PAPI_PREFIX>
./test_papi_combos <EVENTS_PER_RUN> <PAPI_PREFIX>/bin/papi_avail
```

> Note: `install-test-papi-combos.sh` must be run from
> `<PROJECT_DIR>/nugget_util/hook_helper/other_tools/papi`
> so that relative paths work correctly.

#### If `libpfm.so.4` is missing

If you see an error about missing `libpfm.so.4`, install the required library:

```bash
cd <PROJECT_DIR>/nugget_util/hook_helper/other_tools/papi/needed-lib
./install-pfm.sh
export LD_LIBRARY_PATH=$PWD/libpfm/lib:$LD_LIBRARY_PATH
```

You must keep `LD_LIBRARY_PATH` set in any shell where you use this PAPI build.

#### Example output

Example command:

```bash
./test_papi_combos 6 $PWD/aarch64/bin/papi_avail <OUTPUT_FILE>
```

Possible output (truncated):

```text
...
[SUPPORTED] ['PAPI_L1_DCR', 'PAPI_L1_DCW', 'PAPI_L2_DCW', 'PAPI_L1_ICH', 'PAPI_L1_ICA', 'PAPI_L2_TCA'],
[SUPPORTED] ['PAPI_L2_DCR', 'PAPI_L1_DCW', 'PAPI_L2_DCW', 'PAPI_L1_ICH', 'PAPI_L1_ICA', 'PAPI_L2_TCA'],

Tested 376740 combos, 129171 supported (34.3%)

Found a cover of size 5 (theoretical min 5):

[['PAPI_L1_DCM', 'PAPI_L1_ICM', 'PAPI_L2_DCM', 'PAPI_TLB_DM', 'PAPI_L2_LDM', 'PAPI_BR_MSP'],
 ['PAPI_STL_ICY', 'PAPI_HW_INT', 'PAPI_BR_PRC', 'PAPI_BR_INS', 'PAPI_RES_STL', 'PAPI_TOT_CYC'],
 ['PAPI_TOT_INS', 'PAPI_FP_INS', 'PAPI_LD_INS', 'PAPI_SR_INS', 'PAPI_VEC_INS', 'PAPI_LST_INS'],
 ['PAPI_L1_DCA', 'PAPI_L2_DCA', 'PAPI_L1_DCR', 'PAPI_L2_DCR', 'PAPI_L1_DCW', 'PAPI_L2_DCW'],
 ['PAPI_L1_ICM', 'PAPI_TOT_CYC', 'PAPI_SYC_INS', 'PAPI_L1_ICH', 'PAPI_L1_ICA', 'PAPI_L2_TCA']]
```

#### What `test_papi_combos` does

Inputs:

* `<EVENTS_PER_RUN>`: number of events per run (typically equal to the number of hardware counters)
* `papi_avail`: the PAPI availability binary

Workflow:

1. Enumerates possible event combinations of size `<EVENTS_PER_RUN>`.
2. Filters to combinations supported by the hardware.
3. Finds a minimal set of combinations that covers all supported events.
4. Outputs the minimal set of combinations to the output file path. If the path is not specified, it outputs to `papi_combo_cover.txt`.

In the example above:

* You need **5 runs** to cover all events.
* Each run collects **6 events**.
* These combinations are later used when collecting measurements.

Note: For multi-threaded programs, we can reliably measure only overall runtime; detailed per-event measurements are mainly meaningful for single-threaded runs.

---

### 8.5 gem5 `m5ops`

This is required when running Nugget under gem5 (to invoke gem5-specific hooks via `m5` ops).

```bash
cd <PROJECT_DIR>/nugget_util/hook_helper/other_tools/gem5
ISAS="<THE_ABIS_YOU_WANT_TO_INSTALL>" ./get-gem5-util.sh
```

For supported ABIs, see the gem5 documentation:
[https://github.com/gem5/gem5/blob/stable/util/m5/README.md#supported-abis](https://github.com/gem5/gem5/blob/stable/util/m5/README.md#supported-abis)

During the script run, you will be asked whether to use a cross compiler for each ABI. Example:

```bash
ISAS="arm64 riscv" ./get-gem5-util.sh

...
Building for ISA: arm64
Enter CROSS_COMPILE for arm64 (leave blank for none): /usr/bin/aarch64-linux-gnu-
...
scons: done building targets.
Building for ISA: riscv
Enter CROSS_COMPILE for riscv (leave blank for none): /usr/bin/riscv64-linux-gnu-
...
```

After the script finishes, the built m5ops libraries/binaries are placed in per-ABI subdirectories:

```text
$ ls
arm64  get-gem5-util.sh  include  README.md  riscv
```

---

### 8.6 Sniper `sim_api`

This builds the Sniper `sim_api` used by Nugget when running on the Sniper simulator:

```bash
cd <PROJECT_DIR>/nugget_util/hook_helper/other_tools/sniper
make
```
