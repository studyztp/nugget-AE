# Nugget Artifact Evaluation (AE)

This document describes how to set up the environment required to reproduce the experiments in the Nugget paper.

Throughout this document:

- `[project dir]` is the root directory of the cloned Nugget repository.
- `[papi install prefix]` is the directory where PAPI is installed by the helper scripts.

---

## Reproducing Paper Experiments

To make reproduction easier, we provide scripts that automate each step.  
We strongly recommend using the Docker image to control the environment.

In our own experiments, we minimized measurement noise using tools such as `cpuutils`, fixing CPU frequency, and other system-level settings. These are **not** enforced in the AE scripts because they tend to be machine-specific (different tool versions, permissions, etc.). As a result, your reproduced measurements may be noisier than the ones reported in the paper.

### 0. Build and Run the Docker Image

From the project root:

```bash
cd Docker
make image
make NUM_CORES_TO_USE=[max number of cores for the container] WORKDIR=$PWD/.. run
````

Notes:

* Building LLVM uses a lot of memory. Setting `NUM_CORES_TO_USE=$(nproc)` may not be appropriate on all systems. Choose a value that your machine can handle.
* See `Docker/Makefile` for details on how the image and container are built.

Once inside the Docker container (with the project directory mounted as the working directory), run:

```bash
chmod +x install.sh
./install.sh
```

At the end, the script prints a set of environment variable exports.
Copy-paste these into your shell (or add them to your shell startup file) before running the experiments.

---

### 1. Preparation and Interval Analysis

#### 1.1 NPB

Run the preparation and interval analysis for NPB:

```bash
cd nugget-protocol-NPB
python3 ae-scripts/preparation_and_interval_analysis.py -d [project dir]
```

By default, this runs input class **A** with **4 threads** to allow you to see the full pipeline more quickly.

You can change the input class and number of threads:

```bash
python3 ae-scripts/preparation_and_interval_analysis.py \
    -d [project dir] \
    -s [input class, e.g., A,B,C,...] \
    -t [number of threads]
```

Outputs:

* Analysis results (including per-analysis runtime) are under:

  ```text
  nugget-protocol-NPB/ae-experiments/[binary for the input class]/[number of threads]
  ```

Example:

```terminal
dev@99494d3119ed:/workdir/nugget-protocol-NPB/ae-experiments/analysis$ ls
ir_bb_analysis_exe_bt_A  ir_bb_analysis_exe_ep_A  ir_bb_analysis_exe_is_A  ir_bb_analysis_exe_mg_A
ir_bb_analysis_exe_cg_A  ir_bb_analysis_exe_ft_A  ir_bb_analysis_exe_lu_A  ir_bb_analysis_exe_sp_A
dev@99494d3119ed:/workdir/nugget-protocol-NPB/ae-experiments/analysis$ ls ir_bb_analysis_exe_bt_A/
threads-4
dev@99494d3119ed:/workdir/nugget-protocol-NPB/ae-experiments/analysis$ ls ir_bb_analysis_exe_bt_A/threads-4/
execution_time.txt  stderr.log  stdout.log  analysis-output.csv
```

* `analysis-output.csv` contains the LLVM IR basic-block vectors and CSV information referenced in the paper.
* `execution_time.txt` contains the runtime of the analysis itself.

---

### 2. Sample Selection

Run k-means (and optional random sampling) to pick representative regions per benchmark and generate markers:

```bash
cd nugget-protocol-NPB
python3 ae-scripts/sample_selection.py \
    -d [project dir] \
    -s [input class] \
    -b "CG EP" \
    -t [threads] \
    --k [num_clusters]
```

Minimal example (uses defaults for size, benchmarks, etc.):

```bash
python3 ae-scripts/sample_selection.py -d [project dir]
```

Outputs are written under:

```text
nugget-protocol-NPB/ae-experiments
```

---

### 3. Nugget Creation and Sample Validation

Build Nugget and naive binaries for the selected regions, run them, and emit measurement/prediction CSVs:

```bash
cd nugget-protocol-NPB
python3 ae-scripts/nugget_creation_and_validaton.py \
    -d [project dir] \
    -s [input class] \
    -b "CG EP" \
    -t [threads] \
    --grace-perc 0.98
```

What this script does:

* Configures and builds Nugget and naive targets using the selections/markers from the previous step.

* Runs naive binaries to record baseline runtimes, then runs each Nugget binary (handling nested executable paths).

* Aggregates runtimes into:

  ```text
  ae-experiments/nugget-measurement/measurements.csv
  ```

* Computes program-level predicted runtimes using k-means cluster weights and writes prediction errors (k-means and random) to:

  ```text
  ae-experiments/nugget-measurement/prediction-error.csv
  ```

Key options:

* `-s/--size` – input class (A/B/C/…).
* `-b/--benchmarks` – space/comma/semicolon-separated list, e.g. `"CG EP"` or `"CG,EP"`.
* `-t/--threads` – number of threads.
* `--grace-perc` – grace percentage used in marker generation; should match the value used in sample selection.

---

### 4. gem5 Simulation

For gem5-based experiments, see the documentation under:

```text
[project dir]/gem5-experiment
```

---

## Preparation (Environment and Dependencies)

### 1. Dependencies and Tools

Install the base prerequisites (inside the host or Docker, as appropriate):

```bash
sudo apt install build-essential scons python3-dev git pre-commit zlib1g zlib1g-dev \
    libprotobuf-dev protobuf-compiler libprotoc-dev libgoogle-perftools-dev \
    libboost-all-dev libhdf5-serial-dev python3-pydot python3-venv python3-tk mypy \
    m4 libcapstone-dev libpng-dev libelf-dev pkg-config wget cmake doxygen clang-format \
    libncurses-dev
```

Nugget uses `perf` for measurements, so `perf` must be installed and configured with sufficient permissions on the system where you run experiments.

We provide:

* A Docker image under `Docker/` that has the above dependencies preinstalled.
* An `install.sh` script (at the project root) that installs the LLVM toolchain and PAPI.

---

### 1.1 LLVM with Nugget Passes

This builds LLVM with the Nugget analysis and transformation passes.

```bash
cd [project dir]/llvm-project
./build_cmd.sh [llvm install prefix]
```

* Replace `[llvm install prefix]` with the directory where you want LLVM installed.
* After this step, Nugget-enabled `clang`, `opt`, etc. reside under that install prefix (e.g., `[llvm install prefix]/bin`).

#### 1.1.1 Detect Supported CPU Features

Different machines support different feature sets in the LLVM backend. The following script discovers them automatically:

```bash
cd [project dir]/nugget_util/cmake/check-cpu-features
LLVM_BIN=[llvm install prefix]/bin \
LLVM_LIB=[llvm install prefix]/lib \
LLVM_INCLUDE=[llvm install prefix]/include \
    make
./check-cpu-features
```

We separate `LLVM_BIN`, `LLVM_LIB`, and `LLVM_INCLUDE` because package-based LLVM distributions often split them across different directories, e.g.:

* `LLVM_BIN=/usr/bin`
* `LLVM_LIB=/usr/lib/llvm-19/lib`
* `LLVM_INCLUDE=/usr/include/llvm-19/llvm`

Example output in `llc-command.txt`:

```bash
$ cat llc-command.txt
-mcpu=neoverse-n1 -mtriple=aarch64-unknown-linux-gnu -mattr="+fp-armv8,+lse,+neon,+crc,+crypto"
```

You can pass this string to `llc` to enable appropriate backend optimizations.

---

### 1.2 PAPI (Hardware Performance Counters)

PAPI is used to collect hardware performance counters in Nugget runs.

```bash
cd [project dir]/nugget_util/hook_helper/other_tools/papi
./get-papi.sh
```

The tool will be installed under:

```text
[project dir]/nugget_util/hook_helper/other_tools/papi/[your system's arch]
```

For example:

```text
[project dir]/nugget_util/hook_helper/other_tools/papi/aarch64
```

We refer to this directory as `[papi install prefix]`.

---

### 1.3 Test and Generate Event Combinations

This step:

* Verifies that PAPI is correctly installed.
* Generates combinations of events so you can cover all supported events in a minimal number of runs, given a fixed number of hardware counters.

We recommend setting `[# of events per run]` equal to the number of hardware counters on your machine.

You can get that by running:

```bash
[papi install prefix]/bin/papi_avail -a
```

Then:

```bash
./install-test-papi-combos.sh [papi install prefix]
./test_papi_combos [# of events per run] [papi install prefix]/bin/papi_avail
```

> Note: `install-test-papi-combos.sh` must be run from
> `[project dir]/nugget_util/hook_helper/other_tools/papi`
> so that relative paths work correctly.

If you see an error about missing `libpfm.so.4`, install the required library:

```bash
cd [project dir]/nugget_util/hook_helper/other_tools/papi/needed-lib
./install-pfm.sh
export LD_LIBRARY_PATH=$PWD/libpfm/lib:$LD_LIBRARY_PATH
```

You must keep `LD_LIBRARY_PATH` set in any shell where you use this PAPI build.

#### Example Output

Example command:

```bash
./test_papi_combos 6 $PWD/aarch64/bin/papi_avail
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

What `test_papi_combos` does:

* Inputs:

  * `[# of events per run]`: number of events per run (typically equal to the number of hardware counters).
  * `papi_avail`: the PAPI availability binary.
* Workflow:

  1. Enumerates possible event combinations of size `[# of events per run]`.
  2. Filters to combinations supported by the hardware.
  3. Finds a minimal set of combinations that covers all supported events.

In the example above:

* You need **5 runs** to cover all events.
* Each run collects **6 events**.
* These combinations are later used when collecting measurements.

Note: For multi-threaded programs, we can reliably measure only overall runtime; detailed per-event measurements are mainly meaningful for single-threaded runs.

---

### 1.4 gem5 m5ops

This is required when running Nugget under gem5 (for invoking gem5-specific hooks via `m5` ops).

```bash
cd [project dir]/nugget_util/hook_helper/other_tools/gem5
ISAS="[the ABIs you want to install]" ./get-gem5-util.sh
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

### 1.5 Sniper `sim_api`

This builds the Sniper `sim_api` used by Nugget when running on the Sniper simulator:

```bash
cd [project dir]/nugget_util/hook_helper/other_tools/sniper
make
```

```
