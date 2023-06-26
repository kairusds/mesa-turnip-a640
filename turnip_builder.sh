#!/bin/sh
nocolor='\033[0m'
deps="meson ninja patchelf unzip curl pip flex bison zip"
workdir="$(pwd)/turnip_workdir"
driverdir="$workdir/turnip_module"
clear

echo "Checking system for required dependencies..."
for deps_chk in $deps;
	do 
		sleep 0.25
		if command -v $deps_chk >/dev/null 2>&1 ; then
			echo -e "$deps_chk found"
		else
			echo -e "$deps_chk not found, can't countinue."
			deps_missing=1
		fi;
	done
	
	if [ "$deps_missing" == "1" ]
		then echo "Please install missing dependencies" && exit 1
	fi

echo "Installing python Mako dependency (if missing) ..." $'\n'
pip install mako &> /dev/null

echo "Creating and entering to work directory ..." $'\n'
mkdir -p $workdir && cd $workdir

# echo "Downloading mesa source (~30 MB) ..." $'\n'
# curl https://gitlab.freedesktop.org/mesa/mesa/-/archive/main/mesa-main.zip --output mesa-main.zip &> /dev/null
###
# echo "Exracting mesa source to a folder ..." $'\n'
# unzip mesa-main.zip &> /dev/null
cd mesa-main

echo "Creating meson cross file ..." $'\n'
ndk="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
cat <<EOF >"android-aarch64"
[binaries]
ar = '$ndk/llvm-ar'
c = ['ccache', '$ndk/aarch64-linux-android33-clang']
cpp = ['ccache', '$ndk/aarch64-linux-android33-clang++', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '-static-libstdc++']
c_ld = 'lld'
cpp_ld = 'lld'
strip = '$ndk/aarch64-linux-android-strip'
pkgconfig = ['env', 'PKG_CONFIG_LIBDIR=NDKDIR/pkgconfig', '/usr/bin/pkg-config']
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

echo "Generating build files ..." $'\n'
meson build-android-aarch64 --cross-file $workdir/mesa-main/android-aarch64 -Dbuildtype=release -Dplatforms=android -Dplatform-sdk-version=30 -Dandroid-stub=true -Dgallium-drivers= -Dvulkan-drivers=freedreno -Dfreedreno-kmds=kgsl -Db_lto=true &> $workdir/meson_log
echo "Compiling build files ..." $'\n'
ninja -C build-android-aarch64 &> $workdir/ninja_log
# echo "Using patchelf to match soname ..."  $'\n'
cp $workdir/mesa-main/build-android-aarch64/src/freedreno/vulkan/libvulkan_freedreno.so $workdir
# cp $workdir/mesa-main/build-android-aarch64/src/android_stub/libhardware.so $workdir
# cp $workdir/mesa-main/build-android-aarch64/src/android_stub/libsync.so $workdir
cp $workdir/mesa-main/build-android-aarch64/src/android_stub/libbacktrace.so $workdir
cd $workdir

# patchelf --set-soname vulkan.adreno.so libvulkan_freedreno.so
# mv libvulkan_freedreno.so vulkan.adreno.so

if ! [ -a libvulkan_freedreno.so ]; then
	echo -e "Build failed!" && exit 1
fi

echo "Creating driver metadata..." $'\n'
mkdir -p $driverdir
cd $driverdir

cat <<EOF >"meta.json"
{
  "schemaVersion": 1,
  "name": "Mesa3D Turnip Driver",
  "description": "Open-source Vulkan driver for Adreno 640",
  "author": "kairusds",
  "packageVersion": "git",
  "vendor": "Mesa",
  "driverVersion": "$MESA_COMMIT_HASH",
  "minApi": 30,
  "libraryName": "libvulkan_freedreno.so"
}
EOF

echo "Copying necessary files to the driver directory..." $'\n'
cp $workdir/libvulkan_freedreno.so $driverdir
# cp $workdir/libhardware.so $driverdir
# cp $workdir/libsync.so $driverdir
cp $workdir/libbacktrace.so $driverdir

driverzip="$workdir/turnip-$MESA_COMMIT_HASH-git.adpkg.zip"
echo "Packing files..." $'\n'
cd $driverdir
zip $driverzip *
if ! [ -a $driverzip ];
	then echo -e "Packing failed!" && exit 1
	else echo -e "All done!" 
fi
