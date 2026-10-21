#!/bin/bash
# fabrique un buildcache Spack local puis reinstalle depuis ce cache
# a lancer sur un noeud avec Spack, par exemple le login du cluster
set -e
for f in 01-spack z00_lmod z00_spack_lmod; do . "/etc/profile.d/$f.sh"; done

rm -rf "$HOME/bc-demo"
mkdir -p "$HOME/bc-demo/mirror"
cd "$HOME/bc-demo"

cat > spack.yaml <<'EOF'
spack:
  specs:
  - zlib@1.3.1%gcc@11.5.0

  concretizer:
    unify: true

  mirrors:
    local: file://@HOME@/bc-demo/mirror

  config:
    install_tree:
      root: @HOME@/bc-demo/store
    source_cache: @HOME@/.spack/cache
    misc_cache: @HOME@/.spack/cache
EOF
sed -i "s|@HOME@|$HOME|g" spack.yaml

echo "=== 1. concretize"
spack -D . concretize
spack -D . find

echo "=== 2. installation depuis les sources"
time spack -D . install
spack -D . find

echo "=== 3. poussee du binaire dans le miroir"
time spack -D . buildcache create -u --update-index local zlib
du -sh "$HOME/bc-demo/mirror"
find "$HOME/bc-demo/mirror" -name '*.json' | head -3

echo "=== 4. desinstallation"
spack -D . uninstall -y zlib
spack -D . find

echo "=== 5. installation depuis le buildcache seul"
time spack -D . install --cache-only --no-check-signature
spack -D . find
echo "=== FIN"
