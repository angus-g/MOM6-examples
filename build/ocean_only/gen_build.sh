#!/usr/bin/env bash

# recursively expand globs
shopt -s globstar
# case insensitive glob
shopt -s nocaseglob

# preamble, defining variables and rules
cat << 'EOF' > build.ninja
fc = mpifort
cc = cc
ld = mpifort

fflags = -fcray-pointer -fdefault-double-8 -fdefault-real-8 -Waliasing -ffree-line-length-none -fno-range-check -O3
cflags = -D__IFC -O2
cppdefs = -Duse_libMPI -Duse_netCDF -DSPMD

incflags = -I/usr/include -I../shared -I../../src/MOM6/config_src/dynamic -I../../src/MOM6/src/framework
ldflags = -L../shared -lfms -lnetcdff -lnetcdf -lhdf5_hl -lhdf5 -lz

rule fc
    command = $fc $fflags $cppdefs $incflags -c $in

rule cc
    command = $cc $cflags $cppdefs $incflags -c $in

rule link
    command = $ld $in -o $out $ldflags

EOF

# lists of source files
fsrc_files=(../../src/MOM6/src/**/*.F90)
fsrc_files+=(../../src/MOM6/config_src/solo_driver/*.F90)
csrc_files=(../../src/MOM6/src/**/*.c)
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
    deps=$(sed -rn 's/^\s*use\s+(\w+)\b.*/\1/ip' "$file" | uniq | tr '[:upper:]' '[:lower:]')
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

printf 'build MOM6: link ' >> build.ninja
printf '%s ' "${objs[@]}" >> build.ninja
printf '\n' >> build.ninja
