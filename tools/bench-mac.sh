#!/bin/bash
# Speed test on the Mac (docs/speed-test-plan.md): llama.cpp b11685 (commit 13de11e) with Metal, the same GGUFs as the
# PC and the rented GPU (SHA-256 checked), the ladder's KV/batch settings, 3 runs. Run in Terminal:  bash bench-mac.sh
# Then the results are served on the LAN (port 8777) for the PC to fetch; Ctrl-C ends that.
set -uo pipefail
W=~/local-bench-speed; mkdir -p $W/models $W/out; cd $W
pmset -g | grep -q "powermode *2" || echo "NOTE: not in High Power mode (sudo pmset -a powermode 2)"
command -v cmake > /dev/null || { echo "cmake is missing: brew install cmake (and xcode-select --install if there is no compiler), then run this again"; exit 1; }
if [ ! -x llama.cpp/build/bin/llama-bench ]; then
  [ -d llama.cpp/.git ] || git clone -q https://github.com/ggml-org/llama.cpp
  (cd llama.cpp && git checkout -q 13de11e && cmake -B build -DCMAKE_BUILD_TYPE=Release > /dev/null && cmake --build build -j --target llama-bench > /dev/null) || { echo "llama.cpp build failed"; exit 1; }
fi
llama.cpp/build/bin/llama-bench --version 2>&1 | head -2
get() {  # url file bytes: skip a complete file, resume a shorter one, start again on a longer one
  n=$(stat -f %z models/$2 2>/dev/null || echo 0)
  [ "$n" = "$3" ] && { echo "$2 complete"; return; }
  [ "$n" -gt "$3" ] && rm -f models/$2
  echo "downloading $2"; curl -fL --retry 5 -C - -# -o models/$2 "$1"
}
get https://huggingface.co/ggml-org/gpt-oss-20b-GGUF/resolve/15dcfc7e7c608c6161507211ed43c5b590801b4b/gpt-oss-20b-MXFP4.gguf gpt-oss-20b-MXFP4.gguf 12109566624
get https://registry.ollama.ai/v2/library/qwen3-coder/blobs/sha256:1194192cf2a187eb02722edcc3f77b11d21f537048ce04b67ccf8ba78863006a qwen3coder30b.gguf 18556688736
get https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/4ca720788d1e01f1bff70c033e0d0028fd02e502/Qwen3.8-27B-UD-Q4_K_M.gguf Qwen3.8-27B-UD-Q4_K_M.gguf 16464440224
cd models && shasum -a 256 -c <<'S' || { echo "SHA-256 mismatch: stop"; exit 1; }
27cd6c432c7672cb812a92f611cf3ba7bbc35928262bb1e1253ff4ee6ae35901  gpt-oss-20b-MXFP4.gguf
1194192cf2a187eb02722edcc3f77b11d21f537048ce04b67ccf8ba78863006a  qwen3coder30b.gguf
322e194ff79741c7baa497c240f677f54b201b0efab44ca8e50f122b39123482  Qwen3.8-27B-UD-Q4_K_M.gguf
S
cd $W
read -p "Quit Ollama (menu bar icon -> Quit) when the PC says the Mac check is done, then press Enter... "
for m in gpt-oss-20b:gpt-oss-20b-MXFP4.gguf qwen3coder30b:qwen3coder30b.gguf qwen38-27b:Qwen3.8-27B-UD-Q4_K_M.gguf; do
  n=${m%%:*}; f=${m#*:}; echo "$(date +%T) $n"
  sudo powermetrics --samplers cpu_power,gpu_power -i 1000 > out/mac_$n-power.txt 2>/dev/null & P=$!
  llama.cpp/build/bin/llama-bench -m models/$f -ngl 99 -fa on -ctk q8_0 -ctv q8_0 -b 2048 -ub 2048 -r 3 -o json \
    -p 512,4096,16384 -n 128 -d 0,16384 > out/mac_$n.json 2> out/mac_$n.err; echo "exit $?"
  sudo kill $P
done
echo "Done. Serving the results to the PC (Ctrl-C when the PC has them):"; cd out && python3 -m http.server 8777
