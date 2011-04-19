#===============================================================================
# Filename:  boost.sh
# Author:    Pete Goodliffe
# Copyright: (c) Copyright 2009 Pete Goodliffe
# Licence:   Please feel free to use this, with attribution
#===============================================================================
#
# Builds a Boost framework for the iPhone.
# Creates a set of universal libraries that can be used on an iPhone and in the
# iPhone simulator. Then creates a pseudo-framework to make using boost in Xcode
# less painful.
#
# To configure the script, define:
#    BOOST_LIBS:        which libraries to build
#    BOOST_VERSION:     version number of the boost library (e.g. 1_41_0)
#    IPHONE_SDKVERSION: iPhone SDK version (e.g. 3.0)
#
# Then go get the source tar.bz of the boost you want to build, shove it in the
# same directory as this script, and run "./boost.sh". Grab a cuppa. And voila.
#===============================================================================

: ${BOOST_VERSION:=1_44_0}
: ${BOOST_LIBS:="thread signals filesystem regex program_options system"}
: ${IPHONE_SDKVERSION:=4.3}
: ${EXTRA_CPPFLAGS:="-DBOOST_AC_USE_PTHREADS -DBOOST_SP_USE_PTHREADS"}

# The EXTRA_CPPFLAGS definition works around a thread race issue in
# shared_ptr. I encountered this historically and have not verified that
# the fix is no longer required. Without using the posix thread primitives
# an invalid compare-and-swap ARM instruction (non-thread-safe) was used for the
# shared_ptr use count causing nasty and subtle bugs.
#
# Should perhaps also consider/use instead: -BOOST_SP_USE_PTHREADS

: ${TARBALLDIR:=`pwd`}
: ${SRCDIR:=`pwd`/src}
: ${BUILDDIR:=`pwd`/build}
: ${PREFIXDIR:=`pwd`/prefix}
: ${FRAMEWORKDIR:=`pwd`/framework}

BOOST_TARBALL=$TARBALLDIR/boost_$BOOST_VERSION.tar.bz2
    BOOST_SRC=$SRCDIR/boost_${BOOST_VERSION}

#===============================================================================
DEVELOPER="`xcode-select -print-path`"
ARM_DEV_DIR="${DEVELOPER}"/Platforms/iPhoneOS.platform/Developer/usr/bin/
SIM_DEV_DIR="${DEVELOPER}"/Platforms/iPhoneSimulator.platform/Developer/usr/bin/

ARM_COMBINED_LIB=$BUILDDIR/lib_boost_arm.a
SIM_COMBINED_LIB=$BUILDDIR/lib_boost_x86.a

#===============================================================================

echo "BOOST_VERSION:     $BOOST_VERSION"
echo "BOOST_LIBS:        $BOOST_LIBS"
echo "BOOST_TARBALL:     $BOOST_TARBALL"
echo "BOOST_SRC:         $BOOST_SRC"
echo "BUILDDIR:          $BUILDDIR"
echo "PREFIXDIR:         $PREFIXDIR"
echo "FRAMEWORKDIR:      $FRAMEWORKDIR"
echo "IPHONE_SDKVERSION: $IPHONE_SDKVERSION"
echo

#===============================================================================
# Functions
#===============================================================================

abort()
{
    echo
    echo "Aborted: $@"
    exit 1
}

doneSection()
{
    echo
    echo "    ================================================================="
    echo "    Done"
    echo
}

#===============================================================================

cleanFrameworks()
{
    rm -rf "$FRAMEWORKDIR"
    mkdir -p "$FRAMEWORKDIR"
}

#===============================================================================

cleanEverythingReadyToStart()
{
    echo Cleaning everything before we start to build...
    rm -rf $BOOST_SRC
    rm -rf $BUILDDIR
    rm -rf $PREFIXDIR
    doneSection
}

#===============================================================================
unpackBoost()
{
    echo Unpacking boost into $SRCDIR...
    [ -d $SRCDIR ]    || mkdir -p $SRCDIR
    [ -d $BOOST_SRC ] || ( cd $SRCDIR; tar xfj $BOOST_TARBALL )
    [ -d $BOOST_SRC ] && echo "    ...unpacked as $BOOST_SRC"
    doneSection
}

#===============================================================================

writeBjamUserConfig()
{
    # You need to do this to point bjam at the right compiler
    # ONLY SEEMS TO WORK IN HOME DIR GRR
    echo Writing usr-config
    #mkdir -p $BUILDDIR
    #cat > ~/user-config.jam <<EOF
    cat >> $BOOST_SRC/tools/build/v2/user-config.jam <<EOF
using darwin : 4.2.1~iphone
   : "${DEVELOPER}"/Platforms/iPhoneOS.platform/Developer/usr/bin/gcc-4.2 -arch armv7 -mthumb -fvisibility=hidden -fvisibility-inlines-hidden $EXTRA_CPPFLAGS
   : <striper>
   : <architecture>arm <target-os>iphone
   ;
using darwin : 4.2.1~iphonesim
   : "${DEVELOPER}"/Platforms/iPhoneSimulator.platform/Developer/usr/bin/gcc-4.2 -arch i386 -fvisibility=hidden -fvisibility-inlines-hidden $EXTRA_CPPFLAGS
   : <striper>
   : <architecture>x86 <target-os>iphone
   ;
variant = ${RELEASE} ;
EOF
    doneSection
}

#===============================================================================

inventMissingHeaders()
{
    # These files are missing in the ARM iPhoneOS SDK, but they are in the simulator.
    # They are supported on the device, so we copy them from x86 SDK to a staging area
    # to use them on ARM, too.
    echo Invent missing headers
    cp "${DEVELOPER}"/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator${IPHONE_SDKVERSION}.sdk/usr/include/{crt_externs,bzlib}.h $BOOST_SRC
}

#===============================================================================

bootstrapBoost()
{
    cd $BOOST_SRC
    BOOST_LIBS_COMMA=$(echo $BOOST_LIBS | sed -e "s/ /,/g")
    echo "Bootstrapping (with libs $BOOST_LIBS_COMMA)"
    ./bootstrap.sh --with-libraries=$BOOST_LIBS_COMMA
    doneSection
}

#===============================================================================

buildBoostForiPhoneOS_1_44_0()
{
    cd $BOOST_SRC
    threadCount=`hwprefs thread_count`
    ./bjam --prefix="$PREFIXDIR" -j $threadCount toolset=darwin architecture=arm target-os=iphone macosx-version=iphone-${IPHONE_SDKVERSION} define=_LITTLE_ENDIAN link=static variant=${RELEASE} install
    doneSection

    ./bjam -j $threadCount toolset=darwin architecture=x86 target-os=iphone macosx-version=iphonesim-${IPHONE_SDKVERSION} link=static variant=${RELEASE} stage
    doneSection
}

#===============================================================================

# $1: Name of a boost library to lipoficate (technical term)
lipoficate()
{
    : ${1:?}
    NAME=$1
    echo lipoficate: $1
    ARMV6=$BOOST_SRC/bin.v2/libs/$NAME/build/darwin-4.2.1~iphone/${RELEASE}/architecture-arm/link-static/macosx-version-iphone-$IPHONE_SDKVERSION/target-os-iphone/threading-multi/libboost_$NAME.a
    I386=$BOOST_SRC/bin.v2/libs/$NAME/build/darwin-4.2.1~iphonesim/${RELEASE}/architecture-x86/link-static/macosx-version-iphonesim-$IPHONE_SDKVERSION/target-os-iphone/threading-multi/libboost_$NAME.a

    mkdir -p $PREFIXDIR/lib
    lipo \
        -create \
        "$ARMV6" \
        "$I386" \
        -o "$PREFIXDIR/lib/libboost_$NAME.a" \
    || abort "Lipo $1 failed"
}

# This creates universal versions of each individual boost library
lipoAllBoostLibraries()
{
    for i in $BOOST_LIBS; do lipoficate $i; done;
    #
    # Create general, universal libboost.a (and libboost_debug.a) using libtool
    # Note: may be able to get rid of all the un-ar+lipo stuff using libtool
    #
    SUFF=""
    [ $RELEASE != release ] && SUFF="_debug"
    libtool -o "$FRAMEWORKDIR"/libboost${SUFF}.a "$PREFIXDIR"/lib/libboost_*.a

    doneSection
}

scrunchAllLibsTogetherInOneLibPerPlatform()
{
    ALL_LIBS_ARM=""
    ALL_LIBS_SIM=""
    for NAME in $BOOST_LIBS; do
        armLib="$BOOST_SRC/bin.v2/libs/$NAME/build/darwin-4.2.1~iphone/${RELEASE}/architecture-arm/link-static/macosx-version-iphone-$IPHONE_SDKVERSION/target-os-iphone/threading-multi/libboost_$NAME.a"
        intelLib="$BOOST_SRC/bin.v2/libs/$NAME/build/darwin-4.2.1~iphonesim/${RELEASE}/architecture-x86/link-static/macosx-version-iphonesim-$IPHONE_SDKVERSION/target-os-iphone/threading-multi/libboost_$NAME.a"
        ALL_LIBS_ARM="$ALL_LIBS_ARM $armLib";
        ALL_LIBS_SIM="$ALL_LIBS_ARM $intelLib";
        libtool -o $BUILDDIR/libboost_$NAME.a "$armLib" "$intelLib"
    done;

    mkdir -p $BUILDDIR/armv6/obj
    mkdir -p $BUILDDIR/armv7/obj
    mkdir -p $BUILDDIR/i386/obj

    ALL_LIBS=""

    echo Splitting all existing fat binaries...
    for NAME in $BOOST_LIBS; do
        ALL_LIBS="$ALL_LIBS libboost_$NAME.a"
        lipo "$BOOST_SRC/bin.v2/libs/$NAME/build/darwin-4.2.1~iphone/${RELEASE}/architecture-arm/link-static/macosx-version-iphone-$IPHONE_SDKVERSION/target-os-iphone/threading-multi/libboost_$NAME.a" -thin armv6 -o $BUILDDIR/armv6/libboost_$NAME.a
        lipo "$BOOST_SRC/bin.v2/libs/$NAME/build/darwin-4.2.1~iphone/${RELEASE}/architecture-arm/link-static/macosx-version-iphone-$IPHONE_SDKVERSION/target-os-iphone/threading-multi/libboost_$NAME.a" -thin armv7 -o $BUILDDIR/armv7/libboost_$NAME.a
        cp "$BOOST_SRC/bin.v2/libs/$NAME/build/darwin-4.2.1~iphonesim/${RELEASE}/architecture-x86/link-static/macosx-version-iphonesim-$IPHONE_SDKVERSION/target-os-iphone/threading-multi/libboost_$NAME.a" $BUILDDIR/i386/
    done

    echo "Decomposing each architecture's .a files"
    for NAME in $ALL_LIBS; do
        echo Decomposing $NAME...
        (cd $BUILDDIR/armv6/obj; ar -x ../$NAME );
        (cd $BUILDDIR/armv7/obj; ar -x ../$NAME );
        (cd $BUILDDIR/i386/obj; ar -x ../$NAME );
    done

    echo "Linking each architecture into an uberlib ($ALL_LIBS => libboost.a )"
    rm $BUILDDIR/*/libboost.a
    echo ...armv6
    (cd $BUILDDIR/armv6; $ARM_DEV_DIR/ar crus libboost.a obj/*.o; )
    echo ...armv7
    (cd $BUILDDIR/armv7; $ARM_DEV_DIR/ar crus libboost.a obj/*.o; )
    echo ...i386
    (cd $BUILDDIR/i386;  $SIM_DEV_DIR/ar crus libboost.a obj/*.o; )
}

#===============================================================================

                    VERSION_TYPE=Alpha
                  FRAMEWORK_NAME=boost
               FRAMEWORK_VERSION=A

       FRAMEWORK_CURRENT_VERSION=$BOOST_VERSION
 FRAMEWORK_COMPATIBILITY_VERSION=$BOOST_VERSION

buildFramework()
{
    FRAMEWORK_BUNDLE=$FRAMEWORKDIR/$FRAMEWORK_NAME.framework
    # only non-release frameworks have the release in their name
    if [ $RELEASE != release ]; then
        FRAMEWORK_BUNDLE=$FRAMEWORKDIR/${FRAMEWORK_NAME}_$RELEASE.framework
    fi

    rm -rf $FRAMEWORK_BUNDLE

    echo "Framework: Setting up directories..."
    mkdir -p $FRAMEWORK_BUNDLE
    mkdir -p $FRAMEWORK_BUNDLE/Versions
    mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION
    mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Resources
    mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Headers
    mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Documentation

    echo "Framework: Creating symlinks..."
    ln -s $FRAMEWORK_VERSION               $FRAMEWORK_BUNDLE/Versions/Current
    ln -s Versions/Current/Headers         $FRAMEWORK_BUNDLE/Headers
    ln -s Versions/Current/Resources       $FRAMEWORK_BUNDLE/Resources
    ln -s Versions/Current/Documentation   $FRAMEWORK_BUNDLE/Documentation
    ln -s Versions/Current/$FRAMEWORK_NAME $FRAMEWORK_BUNDLE/$FRAMEWORK_NAME

    FRAMEWORK_INSTALL_NAME=$FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/$FRAMEWORK_NAME

    echo "Lipoing library into $FRAMEWORK_INSTALL_NAME..."
    lipo \
        -create \
        -arch armv6 "$BUILDDIR/armv6/libboost.a" \
        -arch armv7 "$BUILDDIR/armv7/libboost.a" \
        -arch i386  "$BUILDDIR/i386/libboost.a" \
        -o          "$FRAMEWORK_INSTALL_NAME" \
    || abort "Lipo $1 failed"

    echo "Framework: Copying includes..."
    cp -r $PREFIXDIR/include/boost/*  $FRAMEWORK_BUNDLE/Headers/

    echo "Framework: Creating plist..."
    cat > $FRAMEWORK_BUNDLE/Resources/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>English</string>
	<key>CFBundleExecutable</key>
	<string>${FRAMEWORK_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>org.boost</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleSignature</key>
	<string>????</string>
	<key>CFBundleVersion</key>
	<string>${FRAMEWORK_CURRENT_VERSION}</string>
</dict>
</plist>
EOF
    doneSection
}

#===============================================================================
# Execution starts here
#===============================================================================

[ -f "$BOOST_TARBALL" ] || abort "Source tarball missing."

mkdir -p $BUILDDIR

case $BOOST_VERSION in
    1_44_0 )
        cleanFrameworks
        for build in release debug; do
            echo ""
            echo "###"
            echo "### building $build"
            echo "###"
            RELEASE=$build
            cleanEverythingReadyToStart
            unpackBoost
            inventMissingHeaders
            writeBjamUserConfig
            bootstrapBoost
            buildBoostForiPhoneOS_1_44_0
            scrunchAllLibsTogetherInOneLibPerPlatform
            lipoAllBoostLibraries
            buildFramework
        done
        ;;
    default )
        echo "This version ($BOOST_VERSION) is not supported"
        ;;
esac

echo "Completed successfully"

#===============================================================================

