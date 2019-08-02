#!/usr/bin/env bash
#  macOS and Linux Bash script to build Rust application hosted on Mynewt OS

set -e  #  Exit when any command fails.
set -x  #  Echo all commands.

set +x ; echo ; echo "----- Building Rust app and Mynewt OS..." ; set -x

#  Rust build profile: debug or release
#  rust_build_profile=debug
rust_build_profile=release

#  Location of the compiled ROM image.  We will remove this to force relinking the Rust app with Mynewt OS.
app_build=$PWD/bin/targets/bluepill_my_sensor/app/apps/my_sensor_app/my_sensor_app.elf

#  Location of the compiled Rust app and external libraries.  The Rust compiler generates a *.rlib archive for the Rust app and each external Rust library here.
rust_build_dir=$PWD/target/thumbv7m-none-eabi/$rust_build_profile/deps

#  Location of the libs/rust_app stub library built by Mynewt.  We will replace this stub by the Rust app and external libraries.
rust_app_dir=$PWD/bin/targets/bluepill_my_sensor/app/libs/rust_app
rust_app_dest=$rust_app_dir/libs_rust_app.a

#  Location of the libs/rust_libcore stub library built by Mynewt.  We will replace this stub by the Rust core library libcore.
rust_libcore_dir=$PWD/bin/targets/bluepill_my_sensor/app/libs/rust_libcore
rust_libcore_dest=$rust_libcore_dir/libs_rust_libcore.a

#  Rust build options
if [ "$rust_build_profile" == 'release' ]; then
    # Build for release
    rust_build_options=--release 
else
    # Build for debug
    rust_build_options= 
fi

#  If this is the very first build, do the Mynewt build to generate the rust_app and rust_libcore stubs.  This build will not link successfully but it's OK.
if [ ! -e $rust_app_dest ]; then
    set +x ; echo ; echo "----- Build Mynewt stubs for Rust app and Rust libcore (ignore error)" ; set -x
    set +e
    newt build bluepill_my_sensor
    set -e
fi

#  Delete the compiled ROM image to force the Mynewt build to relink the Rust app with Mynewt OS.
if [ -e $app_build ]; then
    rm $app_build
fi

#  Delete the compiled Rust app to force the Rust build to relink the Rust app.  Sometimes there are multiple copies of the compiled app, this deletes all copies.
rust_app_build=$rust_build_dir/libapp*.rlib
for f in $rust_app_build
do
    if [ -e $f ]; then
        rm $f
    fi
done

#  TODO: Expand Rust macros
rustup default nightly
set +e  # Ignore errors
pushd rust/mynewt ; cargo rustc -v $rust_build_options -- -Z unstable-options --pretty expanded -Z external-macro-backtrace > ../../logs/libmynewt-expanded.rs ; popd
pushd rust/app    ; cargo rustc -v $rust_build_options -- -Z unstable-options --pretty expanded -Z external-macro-backtrace > ../../logs/libapp-expanded.rs    ; popd
set -e  # Stop on errors

#  Build the Rust app in "src" folder.
set +x ; echo ; echo "----- Build Rust app" ; set -x
cargo build -v $rust_build_options

#  Export the metadata for the Rust build.
cargo metadata --format-version 1 >logs/libapp.json

#  Create rustlib, the library that contains the compiled Rust app and its dependencies (except libcore).  Create in temp folder named "tmprustlib"
set +x ; echo ; echo "----- Consolidate Rust app and external libraries" ; set -x
if [ -d tmprustlib ]; then
    rm -r tmprustlib
fi
if [ ! -d tmprustlib ]; then
    mkdir tmprustlib
fi
pushd tmprustlib

#  Extract the object (*.o) files in the compiled Rust output (*.rlib).
set +x
rust_build=$rust_build_dir/*.rlib
for f in $rust_build
do
    if [ -e $f ]; then
        echo "arm-none-eabi-ar x $f"
        arm-none-eabi-ar x $f
    fi
done

#  Archive the object (*.o) files into rustlib.a.
echo "arm-none-eabi-ar r rustlib.a *.o"
arm-none-eabi-ar r rustlib.a *.o
set -x

#  Overwrite libs_rust_app.a in the Mynewt build by rustlib.a.  libs_rust_app.a was originally created from libs/rust_app.
if [ ! -d $rust_app_dir ]; then
    mkdir -p $rust_app_dir
fi
cp rustlib.a $rust_app_dest
touch $rust_app_dest

#  Dump the ELF and disassembly for the compiled Rust application and libraries (except libcore)
arm-none-eabi-objdump -t -S            --line-numbers --wide rustlib.a >../logs/rustlib.S 2>&1
arm-none-eabi-objdump -t -S --demangle --line-numbers --wide rustlib.a >../logs/rustlib-demangle.S 2>&1

#  Return to the parent directory.
popd

#  Copy Rust libcore to libs_rust_libcore.a, which is originally generated by libs/rust_libcore.
set +x ; echo ; echo "----- Copy Rust libcore" ; set -x
#  Get the Rust compiler sysroot e.g. /Users/Luppy/.rustup/toolchains/nightly-2019-05-22-x86_64-apple-darwin
rust_sysroot=`rustc --print sysroot --target thumbv7m-none-eabi`
#  Get the libcore file in the sysroot.
rust_libcore_src=$rust_sysroot/lib/rustlib/thumbv7m-none-eabi/lib/libcore-*.rlib
#  Copy libcore to the Mynewt build folder.
if [ ! -d $rust_libcore_dir ]; then
    mkdir -p $rust_libcore_dir
fi
if [ -e $rust_libcore_dest ]; then
    rm $rust_libcore_dest
fi
for f in $rust_libcore_src
do
    cp $f $rust_libcore_dest
    touch $rust_libcore_dest
done

#  Dump the ELF and disassembly for the compiled Rust application.
set +e
arm-none-eabi-readelf -a --wide target/thumbv7m-none-eabi/$rust_build_profile/libapp.rlib >logs/libapp.elf 2>&1
arm-none-eabi-objdump -t -S            --line-numbers --wide target/thumbv7m-none-eabi/$rust_build_profile/libapp.rlib >logs/libapp.S 2>&1
arm-none-eabi-objdump -t -S --demangle --line-numbers --wide target/thumbv7m-none-eabi/$rust_build_profile/libapp.rlib >logs/libapp-demangle.S 2>&1
set -e

#  Run the Mynewt build, which will link with the Rust app, Rust libraries and libcore.
#  For verbose build: newt build -v -p bluepill_my_sensor
set +x ; echo ; echo "----- Build and link Mynewt with Rust app" ; set -x
newt build bluepill_my_sensor

#  Display the image size.
newt size -v bluepill_my_sensor
