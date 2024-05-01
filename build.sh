#! /bin/bash
# shellcheck disable=SC2154
#
# Script For Building Android arm64 Kernel
#
# Copyright (c) 2018-2021 Panchajanya1999 <rsk52959@gmail.com>
# Copyright (c) 2021 The Atom-X Developers
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Kernel building script

TOKEN="$BOT_API_KEY"

# Bail out if script fails
set -e

# Function to show an informational message
msg() {
	echo
	echo -e "\e[1;32m$*\e[0m"
	echo
}

err() {
	echo -e "\e[1;41m$*\e[0m"
	exit 1
}

cdir() {
	cd "$1" 2>/dev/null || \
	err "The directory $1 doesn't exists !"
}

##------------------------------------------------------##
##----------Basic Informations, COMPULSORY--------------##

# The defult directory where the kernel should be placed
KERNEL_DIR="$(pwd)"
cd $KERNEL_DIR
BASEDIR="$(basename "$KERNEL_DIR")"

#Clang Directory
CLANG_DIR=$HOME/kernel-prebuilts

# The name of the device for which the kernel is built
MODEL="Xiaomi POCO F1"

# The codename of the device
DEVICE="beryllium"

# The defconfig which should be used. Get it from config.gz from
# your device or check source
DEFCONFIG="$DEVICE"_defconfig

# Show manufacturer info
MANUFACTURERINFO="Xiaomi"

# Specify compiler.
# 'clang' or 'clangxgcc' or 'gcc'
COMPILER=clang

# Kernel is LTO
LTO=0

# Specify linker.
# 'ld.lld'(default)
LINKER=ld.lld

# Clean source prior building. 1 is NO(default) | 0 is YES
INCREMENTAL=1

# Build modules. 0 = NO | 1 = YES
MODULES=0

# Push ZIP to Telegram. 1 is YES | 0 is NO(default)
PTTG=1
	if [ $PTTG = 1 ]
	then
		# Set Telegram Chat ID
		CHATID="$CHANNEL_ID"
	fi

# Generate a full DEFCONFIG prior building. 1 is YES | 0 is NO(default)
DEF_REG=0

# Files/artifacts
FILES=Image.gz-dtb

# Sign the zipfile
# 1 is YES | 0 is NO
SIGN=1
	if [ $SIGN = 1 ]
	then
		#Check for java
		if command -v java > /dev/null 2>&1; then
			SIGN=1
		else
			SIGN=0
		fi
	fi

# Silence the compilation
# 1 is YES(default) | 0 is NO
SILENCE=0

# Debug purpose. Send logs on every successfull builds
# 1 is YES | 0 is NO(default)
LOG_DEBUG=0

##------------------------------------------------------##
##---------Do Not Touch Anything Beyond This------------##

# Check if we are using a dedicated CI ( Continuous Integration ), and
# set KBUILD_BUILD_VERSION and KBUILD_BUILD_HOST and CI_BRANCH

## Set defaults first
CI=DRONE
DISTRO=$(source /etc/os-release && echo "${NAME}")
KBUILD_BUILD_HOST=$(uname -a | awk '{print $2}')
CI_BRANCH=$(git rev-parse --abbrev-ref HEAD)
TERM=xterm
export KBUILD_BUILD_HOST CI_BRANCH TERM

## Check for CI
	if [ $CI = "CIRCLECI" ]
	then
		export KBUILD_BUILD_VERSION=$CIRCLE_BUILD_NUM
		export KBUILD_BUILD_HOST="CircleCI"
		export CI_BRANCH=$CIRCLE_BRANCH
	fi
	if [ $CI = "DRONE" ]
	then
		export KBUILD_BUILD_VERSION=$DRONE_BUILD_NUMBER
		export KBUILD_BUILD_HOST=$DRONE_SYSTEM_HOST
		export CI_BRANCH=$DRONE_BRANCH
		export BASEDIR=$DRONE_REPO_NAME # overriding
		export SERVER_URL="https://cloud.drone.io/resist15/${DRONE_REPO_NAME}/${KBUILD_BUILD_VERSION}/1/2"
	else
		echo "Not presetting Build Version"
	fi

#Check Kernel Version
LINUXVER=$(make kernelversion)

# Set a commit head
COMMIT_HEAD=$(git log --oneline -1)

# Set Date
DATE=$(TZ=Asia/Kolkata date +"%Y-%m-%d")

# Now Its time for other stuffs like cloning, exporting, etc

clone() {
	echo " "
	if [ $COMPILER = "clang" ]
	then
		msg "|| Cloning Playground Clang 17 ||"
		git clone --depth=1 https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-playground -b 17 $CLANG_DIR/clang
		# Toolchain Directory defaults to clang
		TC_DIR=$CLANG_DIR/clang
	fi
	if [ $COMPILER = "gcc" ]
	then
		msg "|| Cloning GCC 12.0.0 Baremetal ||"
		git clone --depth=1 https://github.com/mvaisakh/gcc-arm64 $CLANG_DIR/gcc64
		git clone --depth=1 https://github.com/mvaisakh/gcc-arm $CLANG_DIR/gcc32
		GCC64_DIR=$CLANG_DIR/gcc64
		GCC32_DIR=$CLANG_DIR/gcc32
	fi
	if [ $COMPILER = "clangxgcc" ]
	then
		msg "|| Cloning Clang-14 ||"
		git clone --depth=1 https://gitlab.com/ElectroPerf/atom-x-clang $CLANG_DIR/clang
		# Toolchain Directory defaults to clang
		TC_DIR=$CLANG_DIR/clang

		msg "|| Cloning GCC 12.0.0 Baremetal ||"
		git clone --depth=1 https://github.com/mvaisakh/gcc-arm64 $CLANG_DIR/gcc64
		git clone --depth=1 https://github.com/mvaisakh/gcc-arm $CLANG_DIR/gcc32
		GCC64_DIR=$CLANG_DIR/gcc64
		GCC32_DIR=$CLANG_DIR/gcc32
	fi

	msg "|| Cloning Anykernel ||"
        git clone --depth 1 https://github.com/paranoid-sdm845/AnyKernel3 $CLANG_DIR/AnyKernel3
	AK_DIR=$CLANG_DIR/AnyKernel3
}

##----------------------------------------------------------##

# Function to replace defconfig versioning
setversioning() {
	# For staging branch
	KERNELNAME="PixelOS-$LINUXVER-$DEVICE-$(TZ=Asia/Dhaka date +"%Y-%m-%d-%s")"
	# Export our new localversion and zipnames
	export KERNELNAME
}

##--------------------------------------------------------------##

exports() {
	export KBUILD_BUILD_USER="AtomX-Developers"
	export ARCH=arm64
	export SUBARCH=arm64

	if [ $COMPILER = "clang" ]
	then
		KBUILD_COMPILER_STRING=$("$TC_DIR"/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
		PATH=$TC_DIR/bin/:$TC_DIR/aarch64-linux-gnu/bin/:$PATH
	elif [ $COMPILER = "clangxgcc" ]
	then
		KBUILD_COMPILER_STRING=$("$TC_DIR"/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
		PATH=$TC_DIR/bin:$GCC64_DIR/bin:$GCC32_DIR/bin:/usr/bin:$PATH
	elif [ $COMPILER = "gcc" ]
	then
		KBUILD_COMPILER_STRING=$("$GCC64_DIR"/bin/aarch64-elf-gcc --version | head -n 1)
		PATH=$GCC64_DIR/bin/:$GCC32_DIR/bin/:/usr/bin:$PATH
	fi

	if [ $LTO = "1" ];then
	export LD=ld.lld
        export LD_LIBRARY_PATH=$TC_DIR/lib
	fi

	BOT_MSG_URL="https://api.telegram.org/bot$TOKEN/sendMessage"
	BOT_BUILD_URL="https://api.telegram.org/bot$TOKEN/sendDocument"
	PROCS=$(nproc --all)

	export  KBUILD_BUILD_USER ARCH SUBARCH PATH \
		KBUILD_COMPILER_STRING BOT_MSG_URL \
		BOT_BUILD_URL PROCS TOKEN PATH
}

##---------------------------------------------------------##

tg_post_msg() {
	curl -s -X POST "$BOT_MSG_URL" -d chat_id="$CHATID" \
	-d "disable_web_page_preview=true" \
	-d "parse_mode=html" \
	-d text="$1"

}

##---------------------------------------------------------##

tg_post_build() {
	#Post MD5Checksum alongwith for easeness
	MD5CHECK=$(md5sum "$1" | cut -d' ' -f1)

	#Show the Checksum alongwith caption
	curl --progress-bar -F document=@"$1" "$BOT_BUILD_URL" \
	-F chat_id="$CHATID"  \
	-F "disable_web_page_preview=true" \
	-F "parse_mode=html" \
	-F caption="$2 | <b>MD5 Checksum : </b><code>$MD5CHECK</code>"
}

##----------------------------------------------------------##

# tg_send_sticker() {
# 	curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendSticker" \
# 	-d sticker="$1" \
# 	-d chat_id="$CHATID"
# }

##----------------------------------------------------------------##

tg_send_files(){
	KernelFiles="$(pwd)/$ZIP_FINAL.zip"
	MD5CHECK=$(md5sum "$KernelFiles" | cut -d' ' -f1)
	SID="CAACAgUAAxkBAAIlv2DEzB-BSFWNyXkkz1NNNOp_pm2nAAIaAgACXGo4VcNVF3RY1YS8HwQ"
	STICK="CAACAgUAAxkBAAIlwGDEzB_igWdjj3WLj1IPro2ONbYUAAIrAgACHcUZVo23oC09VtdaHwQ"
	MSG="✅ <b>Build Done</b>
- <code>$((DIFF / 60)) minute(s) $((DIFF % 60)) second(s) </code>

<b>MD5 Checksum</b>
- <code>$MD5CHECK</code>

<b>Zip Name</b>
- <code>$ZIP_FINAL.zip</code>"

        curl --progress-bar -F document=@"$KernelFiles" "https://api.telegram.org/bot$TOKEN/sendDocument" \
        -F chat_id="$CHATID"  \
        -F "disable_web_page_preview=true" \
        -F "parse_mode=html" \
        -F caption="$MSG"

	# tg_send_sticker "$SID"
}

##----------------------------------------------------------##

build_kernel() {
	if [ $INCREMENTAL = 0 ]
	then
		msg "|| Cleaning Sources ||"
		make clean && make mrproper && rm -rf out
	fi

	if [ "$PTTG" = 1 ]
 	then
            tg_post_msg "<b>🔨 PixelOS Kernel Build Triggered</b>

<b>Docker OS: </b><code>$DISTRO</code>

<b>Host Core Count : </b><code>$PROCS</code>

<b>Device: </b><code>$MODEL</code>

<b>Codename: </b><code>$DEVICE</code>

<b>Build Date: </b><code>$DATE</code>

<b>Kernel Name: </b><code>PixelOS-$DEVICE</code>

<b>Linux Tag Version: </b><code>$LINUXVER</code>

<b>Compiler Info: </b><code>$KBUILD_COMPILER_STRING</code>

#PixelOS #Kernel  #$DEVICE"

	# tg_send_sticker "CAACAgQAAxkBAAIl2WDE8lfVkXDOvNEHqCStooREGW6rAAKZAAMWWwwz7gX6bxuxC-ofBA"

	fi

	if [ $SILENCE = "1" ]
	then
		MAKE+=( -s )
	fi

	msg "|| Make Defconfig ||"
	make O=out -j"$PROCS" \
		$DEFCONFIG \
		CROSS_COMPILE=aarch64-linux-gnu- \
		CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
		CC=clang \
		PYTHON=python3 \
		LLVM_IAS=1 \
		LLVM=1 \
		LD="$LINKER" \
		LD_LIBRARY_PATH=$TC_DIR/lib

	if [ $DEF_REG = 1 ]
	then
		cp .config arch/arm64/configs/$DEFCONFIG
		git add arch/arm64/configs/$DEFCONFIG
		git commit -m "$DEFCONFIG: Regenerate"
	fi

	BUILD_START=$(date +"%s")

	if [ $COMPILER = "clang" ]
	then
		MAKE+=(
			CROSS_COMPILE=aarch64-linux-gnu- \
			CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
			CC=clang \
			AR=llvm-ar \
			OBJDUMP=llvm-objdump \
			STRIP=llvm-strip \
			LLVM_IAS=1 \
			LLVM=1 \
			LD="$LINKER" \
			LD_LIBRARY_PATH=$TC_DIR/lib

		)
	elif [ $COMPILER = "gcc" ]
	then
		MAKE+=(
			CROSS_COMPILE_ARM32=arm-eabi- \
			CROSS_COMPILE=aarch64-elf- \
			AR=aarch64-elf-ar \
			OBJDUMP=aarch64-elf-objdump \
			STRIP=aarch64-elf-strip \
			LD=aarch64-elf-"$LINKER" \
			LD_LIBRARY_PATH=$TC_DIR/lib
		)
	elif [ $COMPILER = "clangxgcc" ]
	then
		MAKE+=(
			CC=clang \
			CROSS_COMPILE=aarch64-linux-gnu- \
			CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
			AR=llvm-ar \
			AS=llvm-as \
			NM=llvm-nm \
			STRIP=llvm-strip \
			OBJCOPY=llvm-objcopy \
			OBJDUMP=llvm-objdump \
			OBJSIZE=llvm-size \
			READELF=llvm-readelf \
			HOSTCC=clang \
			HOSTCXX=clang++ \
			HOSTAR=llvm-ar \
			CLANG_TRIPLE=aarch64-linux-gnu- \
			LLVM_IAS=1 \
			LLVM=1 \
			LD="$LINKER" \
			LD_LIBRARY_PATH=$TC_DIR/lib
		)
	fi
	msg "|| Started Compilation ||"
	make -j"$PROCS" O=out \
		NM=llvm-nm \
		OBJCOPY=llvm-objcopy \
		PYTHON=python3 \
		V=0 \
		"${MAKE[@]}" 2>&1 | tee build.log
	if [ $MODULES = "1" ]
	then
	    msg "|| Started Compiling Modules ||"
	    make -j"$PROCS" O=out \
		 "${MAKE[@]}" modules_prepare
	    make -j"$PROCS" O=out \
		 "${MAKE[@]}" modules INSTALL_MOD_PATH="$KERNEL_DIR"/out/modules
	    make -j"$PROCS" O=out \
		 "${MAKE[@]}" modules_install INSTALL_MOD_PATH="$KERNEL_DIR"/out/modules
	    find "$KERNEL_DIR"/out/modules -type f -iname '*.ko' -exec cp {} "$AK_DIR"/modules/system/lib/modules/ \;
	fi

		BUILD_END=$(date +"%s")
		DIFF=$((BUILD_END - BUILD_START))

		if [ -f $KERNEL_DIR/out/arch/arm64/boot/$FILES ]
		then
			msg "|| Kernel successfully compiled ||"
			gen_zip
		else
			if [ "$PTTG" = 1 ]
 			then
				tg_post_msg "<b>❌Error! Compilaton failed: Kernel Image missing</b>

<b>Build Date: </b><code>$DATE</code>

<b>Kernel Name: </b><code>PixelOS-$DEVICE</code>

<b>Linux Tag Version: </b><code>$LINUXVER</code>

<b>Atom-X Build Failure Logs: </b><a href='$SERVER_URL'> Check Here </a>

<b>Time Taken: </b><code>$((DIFF / 60)) minute(s) $((DIFF % 60)) second(s)</code>

<b>Sed Loif Lmao</b>"

				# tg_send_sticker "CAACAgUAAxkBAAIl1WDE8FQjVXrayorUvfFq4A7Uv9FwAAKaAgAChYYpVutaTPLAAra3HwQ"

				exit -1
			fi
		fi

}

##--------------------------------------------------------------##

gen_zip() {
	msg "|| Zipping into a flashable zip ||"
	mv "$KERNEL_DIR"/out/arch/arm64/boot/Image.gz-dtb $AK_DIR/Image.gz-dtb

	cd $AK_DIR
	sed -i "s/kernel.string=.*/kernel.string=Atom-X/g" anykernel.sh
	sed -i "s/kernel.compiler=.*/kernel.compiler=$KBUILD_COMPILER_STRING/g" anykernel.sh
	sed -i "s/kernel.made=.*/kernel.made=Sourav/g" anykernel.sh
	sed -i "s/kernel.version=.*/kernel.version=$LINUXVER/g" anykernel.sh
	sed -i "s/message.word=.*/message.word=Appreciate your efforts for choosing Atom-X kernel./g" anykernel.sh
	sed -i "s/build.date=.*/build.date=$DATE/g" anykernel.sh

	cd $AK_DIR
	zip -r9 "$KERNELNAME.zip" * -x .git README.md .gitignore *.zip

	if [ $SIGN = 1 ]
	then
		## Sign the zip before sending it to telegram
		if [ "$PTTG" = 1 ]
 		then
 			msg "|| Signing Zip ||"
			tg_post_msg "<code>Signing Zip file with AOSP keys..</code>"
 		fi
		cd $AK_DIR
		curl -sLo zipsigner-3.0.jar https://github.com/Magisk-Modules-Repo/zipsigner/raw/master/bin/zipsigner-3.0-dexed.jar
		java -jar zipsigner-3.0.jar $KERNELNAME.zip $KERNELNAME-signed.zip

		## Prepare a final zip variable
		ZIP_FINAL="$KERNELNAME-signed"
	else
		## Prepare a final zip variable
		ZIP_FINAL="$KERNELNAME"
	fi

	if [ "$PTTG" = 1 ]
 	then
		tg_send_files "$1"
	fi
}

clone
setversioning
exports
build_kernel

##-------------------------*****-----------------------------##
