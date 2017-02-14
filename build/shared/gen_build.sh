#!/usr/bin/env bash

# recursively expand globs
shopt -s globstar

# preamble, defining variables and rules
cat << 'EOF' > build.ninja
fc = mpif90
cc = mpicc
ld = mpif90
ar = ar

fflags = -fcray-pointer -fdefault-real-8 -fdefault-double-8 -Waliasing -ffree-line-length-none -fno-range-check -I/usr/include -O3
cflags = -D__IFC -O2
cppdefs = -Duse_libMPI -Duse_netCDF -DSPMD
incflags = -I../../src/FMS/include -I../../src/FMS/mosaic -I../../src/FMS/drifters -I../../src/FMS/fms -I../../src/FMS/mpp/include
ldflags = -lnetcdff -lnetcdf -lhdf5_hl -lhdf5 -lz
arflags = rv

rule fc
    command = $fc $fflags $cppdefs $incflags -c $in

rule cc
    command = $cc $cflags $cppdefs $incflags -c $in

rule link
    command = $ld $in -o $out $ldflags

rule archive
    command = $ar $arflags $out $in

EOF

# lists of source files
fsrc_files=(../../src/FMS/**/*.[fF]90)
csrc_files=(../../src/FMS/**/*.c)
objs=()

# c file rules
for file in "${csrc_files[@]}"; do
    obj="$(basename "${file%.*}").o"
    objs+=("$obj")
    printf 'build %s: cc %s\n' "$obj" "$file" >> build.ninja
done

# build module provides for f files
declare -A modules
declare -A products
for file in "${fsrc_files[@]}"; do
    provided=$(sed -rn '/\bprocedure\b/I! s/^\s*module\s+(\w+).*/\1/ip' "$file" | tr '[:upper:]' '[:lower:]')
    for m in $provided; do
        modules[$m]=$file
        products[$file]+="${m}.mod "
    done
done

# f file rules
for file in "${fsrc_files[@]}"; do
    deps=$(sed -rn 's/^\s*use\s+(\w+).*/\1/ip' "$file" | uniq | tr '[:upper:]' '[:lower:]')
    mods=()

    for dep in $deps; do
        if [[ ! -z ${modules[$dep]} && ${modules[$dep]} != $file ]]; then
            mods+=("$(basename "${modules[$dep]%.*}").o")
        fi
    done

    obj="$(basename "${file%.*}").o"

    printf 'build %s %s: fc %s%s' "$obj" "${products[$file]}" "$file" "${mods[@]+ | }" >> build.ninja
    printf '%s ' "${mods[@]}" >> build.ninja
    printf '\n' >> build.ninja

    objs+=("$obj")
done

printf 'build libfms.a: archive ' >> build.ninja
printf '%s ' "${objs[@]}" >> build.ninja
printf '\n' >> build.ninja
