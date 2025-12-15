# Nugget Artifact Evaluation (AE)

## Zenodo 

DOI: https://doi.org/10.5281/zenodo.17934862

## Intro

This repository is the Artifact Evaluation (AE) workspace for **Nugget**. It contains:
- Docker support for a controlled environment
- Helper scripts to build dependencies (LLVM + Nugget passes, PAPI)
- Experiment pipelines for:
  - **NPB** (`nugget-protocol-NPB/`)
  - **LSMS** (`nugget-protocol-lsms/`)
  - **gem5 simulation** (`gem5-simulation/`)

We recommend the **Docker path** for the smoothest experience. Host installs are supported but more sensitive to system differences.

This README focuses on the minimum required to reproduce the artifacts and the Nugget workflow. 
Please refer to the [expanded guide](expanded-guide.md) for more detailed explanations.

Note on architectures: All AE scripts support selecting the target CPU architecture. Use `-a/--architecture` to build and run for a specific architecture (e.g., `x86_64`, `aarch64`). Where relevant, some scripts also distinguish the architecture used during sample selection via `--selection-architecture`.

## Conventions (placeholders used below)

- `<PROJECT_DIR>`: absolute path to the root of this repo (the directory containing `Docker/`, `install.sh`, etc.)
- `<PAPI_PREFIX>`: directory where PAPI is installed by the provided scripts
- `<ARCHITECTURE>`: target CPU architecture (e.g., x86_64, aarch64)
- Shell snippets assume you run them from the correct directory (called out in each step)

---

## Quickstart (recommended): Docker

### 0) Clone the repo (with submodules)

```bash
git clone --recurse-submodules https://github.com/studyztp/nugget-AE.git
cd nugget-AE
export PROJECT_DIR="$PWD"
````

### 1) Build + run the Docker image

```bash
cd Docker
make image
make NUM_CORES_TO_USE=<N> WORKDIR="$PROJECT_DIR" run
```

Notes:

* Building LLVM can be memory-hungry. If the build OOMs, reduce `<N>`.
* See `Docker/Makefile` for the container entrypoint, mounts, and defaults.

### 2) Inside the container: install toolchains

From the container shell (your repo should already be mounted as the working directory):

```bash
cd "$PROJECT_DIR"
chmod +x install.sh
./install.sh
```

At the end, `install.sh` prints environment-variable exports.
**Copy/paste them into your current shell** (or add to `~/.bashrc`) before running experiments.

---

## Reproducing paper experiments

The pipeline is:

1. **Preparation + interval analysis** (build + run IR basic-block analysis)
2. **Sample selection** (k-means and random sampling, marker generation)
3. **Nugget creation + validation** (build nugget/naive binaries, run, collect CSVs)
4. *(Optional)* **gem5 simulation** (build gem5, create disk images, run scripts)

### Measurement noise (important realism)

Your reproduced runtimes may be noisier than the paper’s numbers. In our paper runs, we also used system-level controls (CPU frequency pinning, background-noise reduction, core pinning, etc.). These knobs are not enforced in the AE scripts because they are machine- and permission-dependent.

The AE scripts run one process at a time. 
In our paper experiments, we ran processes in parallel because we could cleanly isolate each process’s environment to maintain measurement accuracy and stability.

---

## 1) Preparation and interval analysis

### 1.1 NPB (multi-threaded supported)

Run preparation + IR basic-block interval analysis:

```bash
cd "$PROJECT_DIR/nugget-protocol-NPB"
python3 ae-scripts/preparation_and_interval_analysis.py -d "$PROJECT_DIR"
```

Defaults are chosen to make the first run fast-ish (input class **A**, **4 threads**). You can select the build/run architecture via `-a/--architecture`.

Help / options:

```bash
python3 ae-scripts/preparation_and_interval_analysis.py --help
```

Outputs:

* Analysis results are under:

  ```text
  nugget-protocol-NPB/ae-experiments/analysis/threads-<T>/<architecture>/<benchmark>_<size>/
  ```

* Key files:

  * `analysis-output.csv`: LLVM IR BB vectors + metadata used by later steps
  * `execution_time.txt`: analysis runtime
  * `stdout.log`, `stderr.log`: logs for debugging

---

### 1.2 LSMS (single-threaded)

LSMS runs are single-threaded.

```bash
cd "$PROJECT_DIR/nugget-protocol-lsms"
python3 ae-script/preparation_and_interval_analysis.py -d "$PROJECT_DIR"
```

Help / options:

```bash
python3 ae-script/preparation_and_interval_analysis.py --help
```

Outputs:

* Analysis results are under:

  ```text
  nugget-protocol-lsms/ae-experiments/analysis/<input-command>/<architecture>/
  ```

---

## 2) Sample selection

### 2.1 NPB

Run k-means (and optional random sampling) to select representative regions and generate markers:

```bash
cd "$PROJECT_DIR/nugget-protocol-NPB"
python3 ae-scripts/sample_selection.py \
  -d "$PROJECT_DIR" \
  -s <INPUT_CLASS> \
  -b "CG EP" \
  -t <THREADS> \
  --k <NUM_CLUSTERS>
```

Minimal example (uses defaults for size/benchmarks/threads; add `-a` to switch arch):

```bash
python3 ae-scripts/sample_selection.py -d "$PROJECT_DIR" -a <ARCHITECTURE>
```

Performance note:

* If PCA projection is slow for high-dimensional BBVs, use random linear projections:

```bash
python3 ae-scripts/sample_selection.py -d "$PROJECT_DIR" --use-random-linear-projections
```

Outputs:

```text
# K-means outputs (per benchmark-size)
nugget-protocol-NPB/ae-experiments/sample-selection/threads-<T>/<architecture>/k-means/<benchmark>_<size>/

# Random selection outputs (per benchmark-size)
nugget-protocol-NPB/ae-experiments/sample-selection/threads-<T>/<architecture>/random/<benchmark>_<size>/

# Marker input files (k-means + random combined)
nugget-protocol-NPB/ae-experiments/create-markers/threads-<T>/<grace-perc>/<architecture>/<benchmark>_<size>/input-files/
```

---

### 2.2 LSMS

Same idea as NPB, but using LSMS’ script directory:

```bash
cd "$PROJECT_DIR/nugget-protocol-lsms"
python3 ae-script/sample_selection.py -d "$PROJECT_DIR"
```

Outputs:

```text
# K-means + random selection outputs for the chosen analysis dir
nugget-protocol-lsms/ae-experiments/sample-selection/k-means/<analysis-dir>/<architecture>/
nugget-protocol-lsms/ae-experiments/sample-selection/random/<analysis-dir>/<architecture>/

# Marker input files
nugget-protocol-lsms/ae-experiments/create-markers/<grace-perc>/<analysis-dir>/<architecture>/input-files/
```

---

## 3) Nugget creation and sample validation

### 3.1 NPB

This step builds **naive** and **nugget** binaries for the selected regions, runs them, and emits measurement + prediction CSVs.

```bash
cd "$PROJECT_DIR/nugget-protocol-NPB"
python3 ae-scripts/nugget_creation_and_validaton.py \
  -d "$PROJECT_DIR" \
  -s <INPUT_CLASS> \
  -b "CG EP" \
  -t <THREADS> \
  --grace-perc <GRACE_PERCENT> \
  -a <ARCHITECTURE> \
  --selection-architecture <ARCH_FOR_SELECTION>
```

What it produces:

* Raw measurements:

  ```text
  nugget-protocol-NPB/ae-experiments/nugget-measurement/threads-<T>/<size>/<architecture>/measurements.csv
  ```

* Prediction errors (k-means and random baselines):

  ```text
  nugget-protocol-NPB/ae-experiments/nugget-measurement/threads-<T>/<size>/<architecture>/prediction-error.csv
  ```

Key options:

* `-s/--size`: input class (A/B/C/…)
* `-b/--benchmarks`: space/comma/semicolon-separated list, e.g. `"CG EP"` or `"CG,EP"`
* `-t/--threads`: number of threads
* `--grace-perc`: must match the value used during marker generation / sample selection

---

### 3.2 LSMS (requires PAPI event combinations)

LSMS validation requires a **PAPI event-combination cover file**, because the hardware may not allow measuring all events in one run (limited counter registers), and some systems expose only a subset of events.

> Practical warning: some CPUs / kernel setups may report few or even zero usable PAPI events. If that happens, focus on reproducing runtime-only results first.

#### (A) Generate a PAPI cover file

```bash
cd "$PROJECT_DIR/nugget_util/hook_helper/other_tools/papi"
./test_papi_combos <EVENTS_PER_RUN> "$PWD/<ARCH>/bin/papi_avail" <OUTPUT_FILE>
```

* If `<OUTPUT_FILE>` is omitted, the default is `papi_combo_cover.txt`.
* If no cover is found, reduce `<EVENTS_PER_RUN>`. (That usually increases the number of runs needed to cover all events.)

#### (B) Run LSMS nugget/naive validation

```bash
cd "$PROJECT_DIR/nugget-protocol-lsms"
python3 ae-script/nugget_creation_and_validaton.py \
  -d "$PROJECT_DIR" \
  -p "$PROJECT_DIR/nugget_util/hook_helper/other_tools/papi/papi_combo_cover.txt" \
  -a <ARCHITECTURE> \
  -s <ARCH_FOR_SELECTION>
```

Help / options:

```bash
python3 ae-script/nugget_creation_and_validaton.py --help
```

Outputs:

```text
nugget-protocol-lsms/ae-experiments/nugget-measurement/<input-command>/<architecture>/measurements.csv
nugget-protocol-lsms/ae-experiments/nugget-measurement/<input-command>/<architecture>/prediction-error.csv
```

---

## 4) gem5 simulation (optional because it will take a long time)

See the detailed gem5 instructions in [gem5-simulation/README>.md](gem5-simulation/README.md).

---

# Advanced: environment and dependencies (host installs)

> If you use Docker, you can usually skip this section.

## A) Base dependencies

These mirror what the Docker image installs on Ubuntu 24.04. If you’re not using Docker, install:

```bash
sudo apt update && sudo apt install -y \
  build-essential scons git cmake pkg-config wget \
  libncurses-dev libreadline-dev \
  python3-venv python3-pybind11 pybind11-dev \
  gdb \
  libhdf5-dev libopenblas-dev liblapack-dev \
  openmpi-bin libopenmpi-dev libomp-dev \
  unzip \
  libprotobuf-dev protobuf-compiler libprotoc-dev libgoogle-perftools-dev \
  libboost-all-dev libhdf5-serial-dev python3-pydot python3-tk mypy \
  m4 libcapstone-dev libpng-dev libelf-dev doxygen clang-format \
  qemu-system qemu-utils qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils
```

Python packages (if not using Docker’s prebuilt venv):

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -U pip setuptools wheel
pip install pandas scikit-learn pybind11
```

Nugget uses `perf` for measurements. Ensure `perf` is installed and your user has permission to use it on the machine running experiments.

## B) LLVM with Nugget passes

```bash
cd "<PROJECT_DIR>/llvm-project"
./build_cmd.sh <LLVM_INSTALL_PREFIX>
```

After installation, Nugget-enabled `clang`, `opt`, etc. are under `<LLVM_INSTALL_PREFIX>/bin`.

### Detect supported CPU features for LLVM backend

```bash
cd "<PROJECT_DIR>/nugget_util/cmake/check-cpu-features"
LLVM_BIN="<LLVM_INSTALL_PREFIX>/bin" \
LLVM_LIB="<LLVM_INSTALL_PREFIX>/lib" \
LLVM_INCLUDE="<LLVM_INSTALL_PREFIX>/include" \
  make
./check-cpu-features
```

## C) PAPI

```bash
cd "<PROJECT_DIR>/nugget_util/hook_helper/other_tools/papi"
./get-papi.sh
```

Installed under:

```text
<PROJECT_DIR>/nugget_util/hook_helper/other_tools/papi/<ARCH>/
```

We refer to that as `<PAPI_PREFIX>`.

## D) Test + generate PAPI event combinations

```bash
<PAPI_PREFIX>/bin/papi_avail -a
./install-test-papi-combos.sh <PAPI_PREFIX>
./test_papi_combos <EVENTS_PER_RUN> "<PAPI_PREFIX>/bin/papi_avail"
```

If you see a missing `libpfm.so.4` error:

```bash
cd "<PROJECT_DIR>/nugget_util/hook_helper/other_tools/papi/needed-lib"
./install-pfm.sh
export LD_LIBRARY_PATH="$PWD/libpfm/lib:$LD_LIBRARY_PATH"
```

Keep `LD_LIBRARY_PATH` set in any shell that uses this PAPI build.

## E) gem5 m5ops (only for gem5 runs)

```bash
cd "<PROJECT_DIR>/nugget_util/hook_helper/other_tools/gem5"
ISAS="<ISA_LIST>" ./get-gem5-util.sh
```

## F) Sniper sim_api (only for Sniper runs)

```bash
cd "<PROJECT_DIR>/nugget_util/hook_helper/other_tools/sniper"
make
```
