PROJECT_DIR=$PWD

if [[ -z "${NUM_CORES_TO_USE:-}" ]]; then
    NUM_CORES_TO_USE="$(nproc)"
fi

echo "Using maximum ${NUM_CORES_TO_USE} cores"

LLVM_DIR=$PROJECT_DIR/llvm-dir

if [[ -d "$LLVM_DIR" ]]; then
    echo "LLVM install dir already exists at: $LLVM_DIR"
    echo "Skipping LLVM build and install."
else
    echo "LLVM not found at $LLVM_DIR; building and installing..."
    cd llvm-project
    chmod +x build_cmd.sh
    ./build_cmd.sh $LLVM_DIR
    cd build
    make -j$NUM_CORES_TO_USE
    make install -j$NUM_CORES_TO_USE
    cd $PROJECT_DIR
fi

cd $PROJECT_DIR/nugget_util/cmake/check-cpu-features
if [[ -f llc-command.txt ]]; then
    echo "llc-command.txt already exists, skipping check-cpu-features."
else
    echo "llc-command.txt not found; building and running check-cpu-features..."
    LLVM_BIN=$LLVM_DIR/bin LLVM_LIB=$LLVM_DIR/lib \
        LLVM_INCLUDE=$LLVM_DIR/include make
    ./check-cpu-features
    cat llc-command.txt
fi

ARCH=$(uname -m)
PAPI_INSTALL_PREFIX="${PROJECT_DIR}/nugget_util/hook_helper/other_tools/papi/${ARCH}"
OTHER_LIB_PATH="${PROJECT_DIR}/nugget_util/hook_helper/other_tools/papi/needed-lib"
LD_LIBRARY_PATH=$PAPI_INSTALL_PREFIX/../../needed-lib/libpfm/lib:$LD_LIBRARY_PATH
cd $OTHER_LIB_PATH/..

if [[ -d "$PAPI_INSTALL_PREFIX" ]]; then
    echo "PAPI install dir already exists at: $PAPI_INSTALL_PREFIX"
    echo "Skipping PAPI build and install."
else
    echo "PAPI not found at $PAPI_INSTALL_PREFIX; building and installing..."
    cd $OTHER_LIB_PATH
    chmod +x install-pfm.sh
    ./install-pfm.sh
    LD_LIBRARY_PATH=$OTHER_LIB_PATH/libpfm/lib:$LD_LIBRARY_PATH
    cd ..
    chmod +x get-papi.sh
    ./get-papi.sh
    chmod +x install-test-papi-combos.sh
    LD_LIBRARY_PATH=$LD_LIBRARY_PATH ./install-test-papi-combos.sh $PAPI_INSTALL_PREFIX
fi

cd $PROJECT_DIR

echo "Please make sure environment variables are set:"
echo export LD_LIBRARY_PATH="${LLVM_DIR}/lib:${PAPI_INSTALL_PREFIX}/lib:${LLVM_DIR}/lib/${ARCH}-unknown-linux-gnu/:${PAPI_INSTALL_PREFIX}/../needed-lib/libpfm/lib:$LD_LIBRARY_PATH"
