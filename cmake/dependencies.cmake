# >= 3.2 required for ExternalProject_Add_StepDependencies
cmake_minimum_required(VERSION 3.2)


include(${PROJECT_SOURCE_DIR}/lib/libappimage/cmake/scripts.cmake)


# the names of the targets need to differ from the library filenames
# this is especially an issue with libcairo, where the library is called libcairo
# therefore, all libs imported this way have been prefixed with lib
import_pkgconfig_target(TARGET_NAME libssl PKGCONFIG_TARGET openssl)
import_pkgconfig_target(TARGET_NAME libfuse PKGCONFIG_TARGET fuse)


if(USE_CCACHE)
    message(STATUS "Using CCache to build AppImageKit dependencies")
    # TODO: find way to use find_program with all possible paths
    # (might differ from distro to distro)
    # these work on Debian and Ubuntu:
    set(CC "/usr/lib/ccache/gcc")
    set(CXX "/usr/lib/ccache/g++")
else()
    set(CC "${CMAKE_C_COMPILER}")
    set(CXX "${CMAKE_CXX_COMPILER}")
endif()

set(CFLAGS ${DEPENDENCIES_CFLAGS})
set(CPPFLAGS ${DEPENDENCIES_CPPFLAGS})
set(LDFLAGS ${DEPENDENCIES_LDFLAGS})


# TODO: allow using system wide mksquashfs
set(mksquashfs_cflags "-DXZ_SUPPORT ${CFLAGS}")

if(NOT xz_LIBRARIES OR xz_LIBRARIES STREQUAL "")
    message(FATAL_ERROR "xz_LIBRARIES not set")
elseif(xz_LIBRARIES MATCHES "\\.a$")
    set(mksquashfs_ldflags "${xz_LIBRARIES}")
else()
    set(mksquashfs_ldflags "-l${xz_LIBRARIES}")
endif()

if(xz_INCLUDE_DIRS)
    set(mksquashfs_cflags "${mksquashfs_cflags} -I${xz_INCLUDE_DIRS}")
endif()
if(xz_LIBRARY_DIRS)
    set(mksquashfs_ldflags "${mksquashfs_ldflags} -L${xz_LIBRARY_DIRS}")
endif()

ExternalProject_Add(mksquashfs
    GIT_REPOSITORY https://github.com/patrickdepinguin/squashfs-tools/
    GIT_TAG 968aa53dd6d2c0831a9af01873441767c06b88d0
    UPDATE_COMMAND ""  # ${MAKE} sure CMake won't try to fetch updates unnecessarily and hence rebuild the dependency every time
    PATCH_COMMAND patch -N -p1 < ${PROJECT_SOURCE_DIR}/src/mksquashfs-mkfs-fixed-timestamp.patch || true
    CONFIGURE_COMMAND ${SED} -i "s|CFLAGS += -DXZ_SUPPORT|CFLAGS += ${mksquashfs_cflags}|g" <SOURCE_DIR>/squashfs-tools/Makefile
    COMMAND ${SED} -i "s|LIBS += -llzma|LIBS += -Bstatic ${mksquashfs_ldflags}|g" <SOURCE_DIR>/squashfs-tools/Makefile
    COMMAND ${SED} -i "s|install: mksquashfs unsquashfs|install: mksquashfs|g" squashfs-tools/Makefile
    COMMAND ${SED} -i "/cp unsquashfs/d" squashfs-tools/Makefile
    BUILD_COMMAND env CC=${CC} CXX=${CXX} LDFLAGS=${LDFLAGS} ${MAKE} -C squashfs-tools/ XZ_SUPPORT=1 mksquashfs
    # ${MAKE} install unfortunately expects unsquashfs to be built as well, hence can't install the binary
    # therefore using built file in SOURCE_DIR
    # TODO: implement building out of source
    BUILD_IN_SOURCE ON
    INSTALL_COMMAND ${MAKE} -C squashfs-tools/ install INSTALL_DIR=<INSTALL_DIR>
)

ExternalProject_Get_Property(mksquashfs INSTALL_DIR)
set(mksquashfs_INSTALL_DIR "${INSTALL_DIR}")
mark_as_advanced(mksquashfs_INSTALL_DIR)

# for later use when packaging as an AppImage
set(mksquashfs_BINARY "${mksquashfs_INSTALL_DIR}/mksquashfs")
mark_as_advanced(mksquashfs_BINARY)


#### build dependency configuration ####

# only have to build custom xz when not using system libxz
if(TARGET xz-EXTERNAL)
    if(TARGET mksquashfs)
        ExternalProject_Add_StepDependencies(mksquashfs configure xz-EXTERNAL)
    endif()
endif()
