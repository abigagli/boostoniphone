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
#    IPHONE_SDKVERSION: iPhone SDK version (e.g. 5.1)
#
# Then go get the source tar.bz of the boost you want to build, shove it in the
# same directory as this script, and run "./boost.sh". Grab a cuppa. And voila.
#===============================================================================

: ${BOOST_LIBS:="thread date_time serialization iostreams signals filesystem regex system python test timer chrono program_options wave"}
#: ${BOOST_LIBS:="thread signals filesystem regex system date_time"}
: ${IPHONE_SDKVERSION:=6.1}
: ${OSX_SDKVERSION:=10.8}
: ${XCODE_ROOT:=`xcode-select -print-path`}
: ${EXTRA_CPPFLAGS:="-DBOOST_AC_USE_PTHREADS -DBOOST_SP_USE_PTHREADS -std=c++11 -stdlib=libc++"}

# The EXTRA_CPPFLAGS definition works around a thread race issue in
# shared_ptr. I encountered this historically and have not verified that
# the fix is no longer required. Without using the posix thread primitives
# an invalid compare-and-swap ARM instruction (non-thread-safe) was used for the
# shared_ptr use count causing nasty and subtle bugs.
#
# Should perhaps also consider/use instead: -BOOST_SP_USE_PTHREADS

# **********+ NOTE *************
# {IOS|OSX}BUILDDIR are for "our" part of the build, i.e. where we disassemble fat libs and objects to
# reassemble them in per-architecture uber-libs
# while osx-build and ios-build are the actual folder where boost build takes place

: ${SRCDIR:=`pwd`}
: ${IOSBUILDDIR:=`pwd`/ios/build}
: ${OSXBUILDDIR:=`pwd`/osx/build}
: ${IOSPREFIXDIR:=`pwd`/ios/INSTALL}
: ${OSXPREFIXDIR:=`pwd`/osx/INSTALL}
: ${IOSFRAMEWORKDIR:=`pwd`/ios/framework}
: ${OSXFRAMEWORKDIR:=`pwd`/osx/framework}

[ -n "$1" ] || BUILD_ALL_FROM_SCRATCH=1
OSX_TOOLSET=${1:-"clang-xcode"}
BOOST_SRC=$SRCDIR/boost

#===============================================================================

ARM_DEV_DIR=$XCODE_ROOT/Platforms/iPhoneOS.platform/Developer/usr/bin/
SIM_DEV_DIR=$XCODE_ROOT/Platforms/iPhoneSimulator.platform/Developer/usr/bin/

#ARM_COMBINED_LIB=$IOSBUILDDIR/lib_boost_arm.a
#SIM_COMBINED_LIB=$IOSBUILDDIR/lib_boost_x86.a

#===============================================================================


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
cleanOSXRelated()
{
    echo Cleaning osx-build/stage and $OSXBUILDDIR before we start to build...
    rm -rf $OSXBUILDDIR
	rm -rf osx-build/stage
    doneSection
}

cleanEverythingReadyToStart()
{
    echo Cleaning everything before we start to build...
	rm -rf iphone-build iphonesim-build osx-build
    rm -rf $IOSBUILDDIR
    rm -rf $OSXBUILDDIR
    rm -rf $IOSPREFIXDIR
    rm -rf $OSXPREFIXDIR
    rm -rf $IOSFRAMEWORKDIR
    rm -rf $OSXFRAMEWORKDIR
    doneSection
}

#===============================================================================
updateBoost()
{
    echo Updating boost into $BOOST_SRC...

	if [ -d $BOOST_SRC ]
	then
		# Remove everything not under version control...
		svn st --no-ignore $BOOST_SRC | egrep '^[?I]' | sed 's:.......::' | xargs rm -rf 

        # Just to be sure we don't have conflicts when updating...
        svn revert libs/context/build/Jamfile.v2

		svn update boost
	else
		BOOST_BRANCH=`svn ls http://svn.boost.org/svn/boost/tags/release/ | sort | tail -1`
		svn co http://svn.boost.org/svn/boost/tags/release/$BOOST_BRANCH boost
	fi

    doneSection
}

patchBuildOflibboost_context()
{
    cd $BOOST_SRC
    svn revert libs/context/build/Jamfile.v2
    patch -p0 -l -i ../libboost_context.patch
    doneSection
}


updateBoostconfig()
{
	#svn st $BOOST_SRC/tools/build/v2/user-config.jam | grep '^M'
	#if [ $? != 0 ]
	#then
    #    cat >> $BOOST_SRC/tools/build/v2/user-config.jam <<EOF
    
    cat > ~/user-config.jam <<EOF
using clang : ToT #Use as "b2 --toolset=clang-ToT" 
   : $LLVMROOT/bin/clang++ -std=c++11 -stdlib=libc++
   : <striper>
   <compileflags>"-arch i386 -arch x86_64 -I$LIBCXXROOT/include"
   <linkflags>"-arch i386 -arch x86_64 -headerpad_max_install_names -L$LIBCXXROOT/lib"
   ;
using clang : xcode #Use as "b2 --toolset=clang-xcode" 
   : $XCODE_ROOT/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++ -std=c++11 -stdlib=libc++
   : <striper> 
   <compileflags>"-arch i386 -arch x86_64"
   <linkflags>"-arch i386 -arch x86_64 -headerpad_max_install_names"
   ;
using clang : xcode32 #Use as "b2 --toolset=clang-xcode32 address-model=32". Needed for libboost_context
   : $XCODE_ROOT/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++ -std=c++11 -stdlib=libc++
   : <striper> 
   <compileflags>"-arch i386"
   <linkflags>"-arch i386 -headerpad_max_install_names"
   ;

using clang : xcode64 #Use as "b2 --toolset=clang-xcode64 address-model=64". Needed for libboost_context
   : $XCODE_ROOT/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++ -std=c++11 -stdlib=libc++
   : <striper> 
   <compileflags>"-arch x86_64"
   <linkflags>"-arch x86_64 -headerpad_max_install_names"
   ;

using darwin : fsfgcc #Use as "b2 --toolset=darwin-fsfgcc" 
   : /Users/abigagli/GCC-CURRENT/bin/g++ -std=c++11
   : <striper>
   <compileflags>"-D_GLIBCXX_USE_NANOSLEEP -D_GLIBCXX_USE_SCHED_YIELD"
   <linkflags>"-headerpad_max_install_names"
   ;
using darwin : ${OSX_SDKVERSION}~macosx #Use as "b2 --toolset=darwin-${OSX_SDKVERSION}~macosx" 
   : $XCODE_ROOT/usr/bin/g++ 
   : <striper>
   <compileflags>"-arch i386 -arch x86_64"
   <linkflags>"-arch i386 -arch x86_64 -headerpad_max_install_names"
   ;
using darwin : ${IPHONE_SDKVERSION}~iphone
   : $XCODE_ROOT/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++ -arch armv6 -arch armv7 -arch armv7s -fvisibility=hidden -fvisibility-inlines-hidden $EXTRA_CPPFLAGS
   : <striper> <root>$XCODE_ROOT/Platforms/iPhoneOS.platform/Developer
   : <architecture>arm <target-os>iphone
   ;
using darwin : ${IPHONE_SDKVERSION}~iphonesim
   : $XCODE_ROOT/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++ -arch i386 -fvisibility=hidden -fvisibility-inlines-hidden $EXTRA_CPPFLAGS
   : <striper> <root>$XCODE_ROOT/Platforms/iPhoneSimulator.platform/Developer
   : <architecture>x86 <target-os>iphone
   ;
EOF
	#fi

    doneSection
}

#===============================================================================

inventMissingHeaders()
{
    # These files are missing in the ARM iPhoneOS SDK, but they are in the simulator.
    # They are supported on the device, so we copy them from x86 SDK to a staging area
    # to use them on ARM, too.
    echo Invent missing headers
    cp $XCODE_ROOT/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator${IPHONE_SDKVERSION}.sdk/usr/include/{crt_externs,bzlib}.h $BOOST_SRC
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

buildBoostForOSX()
{
    cd $BOOST_SRC

    #NOTE: libboost_context build for OSX with clang needs special treatment....
    if [ "$OSX_TOOLSET" = "clang-xcode" ]; then

        mkdir -p $OSXPREFIXDIR/${OSX_TOOLSET}/shared/lib 
        mkdir -p $OSXPREFIXDIR/${OSX_TOOLSET}/static/lib 
        mkdir -p ../osx-build/stage/lib

        #First build the 32 and 64 bit dylibs
        ./b2 --with-context -j16 --build-dir=../osx-build --stagedir=/tmp/libboost_context/32/shared toolset=clang-xcode32 address-model=32 link=shared threading=multi stage
        ./b2 --with-context -j16 --build-dir=../osx-build --stagedir=/tmp/libboost_context/64/shared toolset=clang-xcode64 address-model=64 link=shared threading=multi stage

        #Then lipoficate them 
        $ARM_DEV_DIR/lipo /tmp/libboost_context/32/shared/lib/libboost_context.dylib /tmp/libboost_context/64/shared/lib/libboost_context.dylib -create -output $OSXPREFIXDIR/${OSX_TOOLSET}/shared/lib/libboost_context.dylib 


        #First build the 32 and 64 bit static libs
        ./b2 --with-context -j16 --build-dir=../osx-build --stagedir=/tmp/libboost_context/32/static toolset=clang-xcode32 address-model=32 link=static threading=multi stage
        ./b2 --with-context -j16 --build-dir=../osx-build --stagedir=/tmp/libboost_context/64/static toolset=clang-xcode64 address-model=64 link=static threading=multi stage

        #Then lipoficate them 
        $ARM_DEV_DIR/lipo /tmp/libboost_context/32/static/lib/libboost_context.a /tmp/libboost_context/64/static/lib/libboost_context.a -create -output ../osx-build/stage/lib/libboost_context.a 

        #And for static lib also simulate the install phase with a simple copy
        cp -p ../osx-build/stage/lib/libboost_context.a $OSXPREFIXDIR/${OSX_TOOLSET}/static/lib/libboost_context.a  
    else
        ./b2 --with-context -j16 --build-dir=../osx-build --stagedir=$OSXPREFIXDIR/${OSX_TOOLSET}/shared toolset=${OSX_TOOLSET} link=shared threading=multi stage
        ./b2 --with-context -j16 --build-dir=../osx-build --stagedir=../osx-build/stage --prefix=$OSXPREFIXDIR --libdir=$OSXPREFIXDIR/${OSX_TOOLSET}/static/lib toolset=${OSX_TOOLSET} link=static threading=multi stage install
    fi


    # OSX dylibs: build and stage only
    # NOTE: We _stage_ into OSXPREFIXDIR/... (the install root location) instead of _installing_ there
    # so as to avoid an additional copy of header files. 
    # (which will be copied by the following install for OSX static libs
	./b2 -j16 --build-dir=../osx-build --stagedir=$OSXPREFIXDIR/${OSX_TOOLSET}/shared toolset=${OSX_TOOLSET} link=shared threading=multi stage
    doneSection

    # OSX static libs: build and install. This will copy the header files too
	./b2 -j16 --build-dir=../osx-build --stagedir=../osx-build/stage --prefix=$OSXPREFIXDIR --libdir=$OSXPREFIXDIR/${OSX_TOOLSET}/static/lib toolset=${OSX_TOOLSET} link=static threading=multi stage install

    doneSection
}

buildBoostForiOSAndOSX()
{
    cd $BOOST_SRC

    # add --debug-configuration to check used configuration
    # add --debug-building to see actual compile/link flags passed in
    # add -n for a dry-run
    
    # iOS static libs: build and stage only.
    ./b2 -j16 --build-dir=../iphone-build --stagedir=../iphone-build/stage toolset=darwin-${IPHONE_SDKVERSION}~iphone architecture=arm target-os=iphone macosx-version=iphone-${IPHONE_SDKVERSION} define=_LITTLE_ENDIAN link=static stage
    
    #NOTE:  libboost_context must be built explicitly because it's not been bootstrapped
    ./b2 --with-context -j16 --build-dir=../iphone-build --stagedir=../iphone-build/stage toolset=darwin-${IPHONE_SDKVERSION}~iphone architecture=arm target-os=iphone macosx-version=iphone-${IPHONE_SDKVERSION} define=_LITTLE_ENDIAN link=static stage
    doneSection


    # iOS-simulator static libs: build and stage only
    ./b2 -j16 --build-dir=../iphonesim-build --stagedir=../iphonesim-build/stage toolset=darwin-${IPHONE_SDKVERSION}~iphonesim architecture=x86 target-os=iphone macosx-version=iphonesim-${IPHONE_SDKVERSION} link=static stage

    #NOTE:  libboost_context must be built explicitly because it's not been bootstrapped
    ./b2 --with-context -j16 --build-dir=../iphonesim-build --stagedir=../iphonesim-build/stage toolset=darwin-${IPHONE_SDKVERSION}~iphonesim architecture=x86 target-os=iphone macosx-version=iphonesim-${IPHONE_SDKVERSION} link=static stage
	doneSection

    buildBoostForOSX
}

#===============================================================================

setDylibInstallName()
{
    for file in $OSXPREFIXDIR/${OSX_TOOLSET}/shared/lib/libboost_*.dylib; do
        curinstallname=$(otool -D $file | tail -1) 

        if [[ ! "$curinstallname" == @* ]]; then
            echo "Setting installname for $file"
            install_name_tool -id @rpath/$(basename $file) $file || abort "install_name_tool -id failed"
        else
            echo "installname already relative: $curinstallname"
        fi

        while read line
        do
            libname=$(awk '{print $1}' <<< "$line")

            case $libname in
                /*) tochange=0;;
                @*) tochange=0;;
                 *) tochange=1;;
             esac

             if [ $tochange -eq 1 ]; then
                 echo "changing install name: $libname -> @rpath/$libname"
                 install_name_tool -change $libname @rpath/$libname $file || abort "install_name_tool -change failed"
             fi
         done < <(otool -L $file | grep -v ':')
         echo
     done

     doneSection
}
#===============================================================================

scrunchAllLibsTogetherInOneLibPerPlatform()
{
	cd $SRCDIR

    if [[ $BUILD_ALL_FROM_SCRATCH -eq 1 ]]; then
        mkdir -p $IOSBUILDDIR/armv6/obj
        mkdir -p $IOSBUILDDIR/armv7/obj
        mkdir -p $IOSBUILDDIR/armv7s/obj
        mkdir -p $IOSBUILDDIR/i386/obj
    fi

    mkdir -p $OSXBUILDDIR/i386/obj
    mkdir -p $OSXBUILDDIR/x86_64/obj

    ALL_LIBS=""

    echo Splitting all existing fat binaries...
    for NAME in $(basename iphone-build/stage/lib/*.a); do
    #for NAME in $BOOST_LIBS; do
        ALL_LIBS="$ALL_LIBS $NAME"

        if [[ $BUILD_ALL_FROM_SCRATCH -eq 1 ]]; then
            #iphone libs are fat (armv6, armv7, armv...), so we lipo-thin-ize each lib
            $ARM_DEV_DIR/lipo "iphone-build/stage/lib/$NAME" -thin armv6 -o $IOSBUILDDIR/armv6/$NAME
            $ARM_DEV_DIR/lipo "iphone-build/stage/lib/$NAME" -thin armv7 -o $IOSBUILDDIR/armv7/$NAME
            $ARM_DEV_DIR/lipo "iphone-build/stage/lib/$NAME" -thin armv7s -o $IOSBUILDDIR/armv7s/$NAME
            #iphonesim libs are i386 only, so just copy them instead of lipo-thinize..
            cp "iphonesim-build/stage/lib/$NAME" $IOSBUILDDIR/i386/ 
        fi

        if $ARM_DEV_DIR/lipo "osx-build/stage/lib/$NAME" -info | grep -c 'Non-fat' > /dev/null; then
            #when building with fsfgcc, osx libs are not fat so we assume there's only x86_64 and just copy
            #them because lipo -thin fails if source file is not fat
            cp "osx-build/stage/lib/$NAME" $OSXBUILDDIR/x86_64/$NAME
        else
            osx_fatlibs=1
            #if compiled with clang or xcode's gcc are fat and must be treated as iphone's ones
            $ARM_DEV_DIR/lipo "osx-build/stage/lib/$NAME" -thin i386 -o $OSXBUILDDIR/i386/$NAME
            $ARM_DEV_DIR/lipo "osx-build/stage/lib/$NAME" -thin x86_64 -o $OSXBUILDDIR/x86_64/$NAME
        fi
    done

    echo "Decomposing each architecture's .a files"
    for NAME in $ALL_LIBS; do
        echo Decomposing $NAME...
        if [[ $BUILD_ALL_FROM_SCRATCH -eq 1 ]]; then
            (cd $IOSBUILDDIR/armv6/obj; ar -x ../$NAME );
            (cd $IOSBUILDDIR/armv7/obj; ar -x ../$NAME );
            (cd $IOSBUILDDIR/armv7s/obj; ar -x ../$NAME );
            (cd $IOSBUILDDIR/i386/obj; ar -x ../$NAME );
        fi

        if [[ $osx_fatlibs -eq 1 ]];then
            (cd $OSXBUILDDIR/i386/obj; ar -x ../$NAME );
        fi
        (cd $OSXBUILDDIR/x86_64/obj; ar -x ../$NAME );
    done

    echo "Linking each architecture into an uberlib ($ALL_LIBS => libboost_all.a )"
    if [[ $BUILD_ALL_FROM_SCRATCH -eq 1 ]]; then
        rm $IOSBUILDDIR/*/libboost_all.a
        echo ...armv6
        (cd $IOSBUILDDIR/armv6; $ARM_DEV_DIR/ar crus libboost_all.a obj/*.o; )
        echo ...armv7
        (cd $IOSBUILDDIR/armv7; $ARM_DEV_DIR/ar crus libboost_all.a obj/*.o; )
        echo ...armv7s
        (cd $IOSBUILDDIR/armv7s; $ARM_DEV_DIR/ar crus libboost_all.a obj/*.o; )
        echo ...i386
        (cd $IOSBUILDDIR/i386;  $SIM_DEV_DIR/ar crus libboost_all.a obj/*.o; )
    fi

    rm $OSXBUILDDIR/*/libboost_all.a
    if [[ $osx_fatlibs -eq 1 ]];then
        echo ...osx-i386
        (cd $OSXBUILDDIR/i386;  $SIM_DEV_DIR/ar crus libboost_all.a obj/*.o; )
    fi

    echo ...x86_64
    (cd $OSXBUILDDIR/x86_64;  $SIM_DEV_DIR/ar crus libboost_all.a obj/*.o; )

    echo "Creating universal osx static uberlib into $OSXPREFIXDIR/${OSX_TOOLSET}/static/lib/libboost_all.a"
    $ARM_DEV_DIR/lipo -create $OSXBUILDDIR/*/libboost_all.a -o "$OSXPREFIXDIR/${OSX_TOOLSET}/static/lib/libboost_all.a" || abort "Lipo failed"
}

#===============================================================================
buildFramework()
{
	: ${1:?}
	FRAMEWORKDIR=$1
	BUILDDIR=$2

	VERSION_TYPE=Alpha
	FRAMEWORK_NAME=boost
	FRAMEWORK_VERSION=A

	FRAMEWORK_CURRENT_VERSION=$BOOST_VERSION
	FRAMEWORK_COMPATIBILITY_VERSION=$BOOST_VERSION

    FRAMEWORK_BUNDLE=$FRAMEWORKDIR/$FRAMEWORK_NAME.framework
    echo "Framework: Building $FRAMEWORK_BUNDLE from $BUILDDIR..."

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

    #NOTE: for OSX this step has already been done at the very end of scrunchAllLibsTogetherInOneLibPerPlatform
    #so we could simply copy-rename that one into the frameworks, but this function is called also for building the iOS 
    #framework
    echo "Lipoing library into $FRAMEWORK_INSTALL_NAME..."
    $ARM_DEV_DIR/lipo -create $BUILDDIR/*/libboost_all.a -o "$FRAMEWORK_INSTALL_NAME" || abort "Lipo $1 failed"

    echo "Framework: Copying includes..."
    cp -r $OSXPREFIXDIR/include/boost/*  $FRAMEWORK_BUNDLE/Headers/

    #Create a short-circuit symlink into framework's Headers folder
    #so that setting FRAMEWORK_SEARCH_PATHS in Xcode makes all #include <boost/...>
    #work without requiring to set HEADER_SEARCH_PATHS too (see https://devforums.apple.com/message/595808#595808)
    echo "Framework: Creating 'boost' symlink into Headers" 
    pushd $FRAMEWORK_BUNDLE/Headers
    ln -s . boost
    popd


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

mkdir -p $IOSBUILDDIR

BOOST_VERSION=`svn info $BOOST_SRC | grep URL | sed -e 's/^.*\/Boost_\([^\/]*\)/\1/'`
echo "BOOST_VERSION:     $BOOST_VERSION"
echo "BOOST_LIBS:        $BOOST_LIBS"
echo "BOOST_SRC:         $BOOST_SRC"
echo "IOSBUILDDIR:       $IOSBUILDDIR"
echo "OSXBUILDDIR:       $OSXBUILDDIR"
echo "IOSPREFIXDIR:      $IOSPREFIXDIR"
echo "OSXPREFIXDIR:      $OSXPREFIXDIR"
echo "IOSFRAMEWORKDIR:   $IOSFRAMEWORKDIR"
echo "OSXFRAMEWORKDIR:   $OSXFRAMEWORKDIR"
echo "IPHONE_SDKVERSION: $IPHONE_SDKVERSION"
echo "XCODE_ROOT:        $XCODE_ROOT"
echo "OSX_TOOLSET:       $OSX_TOOLSET"
echo

if [[ $BUILD_ALL_FROM_SCRATCH -eq 1 ]]; then
    echo "*************** REBUILDING ALL FROM SCRATCH **************"
    echo
    cleanEverythingReadyToStart
    updateBoost
    patchBuildOflibboost_context
    updateBoostconfig
    inventMissingHeaders
    bootstrapBoost
    buildBoostForiOSAndOSX
    setDylibInstallName
    scrunchAllLibsTogetherInOneLibPerPlatform
    buildFramework $IOSFRAMEWORKDIR $IOSBUILDDIR
    buildFramework $OSXFRAMEWORKDIR $OSXBUILDDIR
else
    echo "------------ BUILDING OSX ONLY WITH $OSX_TOOLSET -------------"
    cleanOSXRelated
    buildBoostForOSX
    setDylibInstallName

    scrunchAllLibsTogetherInOneLibPerPlatform

    #Build the framework only when using clang-xcode as frameworks
    #will only be used from xcode projects, which will be built with the
    #same clang-xcode tools
    if [ "$OSX_TOOLSET" = "clang-xcode" ]; then
        buildFramework $OSXFRAMEWORKDIR $OSXBUILDDIR
    fi
fi


echo "Completed successfully"

#===============================================================================
