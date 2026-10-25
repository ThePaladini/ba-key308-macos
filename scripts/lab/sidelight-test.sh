#!/bin/zsh
# Guided test for the side light over the 2.4G receiver: each step is announced aloud ("passo um"…);
# note what the side light shows at each step. The log has what the keyboard reports after each step.
export PATH=$HOME/.local/bin:$PATH
LOG=${1:-/tmp/sidelight-test.log}
osascript -e 'quit app "BA-KEY Menu"' 2>/dev/null; sleep 1
: > $LOG
step() { # number, description, command…
  local n=$1 d=$2; shift 2
  say -v Flo "passo $n"
  "$@" >/dev/null 2>&1
  sleep 3
  echo "$n | $d | $(bakey info 2>&1 | grep '^Side light')" | tee -a $LOG
  sleep 1.5
}
bakey info 2>&1 | head -1 | tee -a $LOG
step 1 "vermelho fixo"      bakey effect side static --color ff0000
step 2 "desligada"          bakey effect side off
step 3 "vermelho fixo"      bakey effect side static --color ff0000
step 4 "desligada"          bakey effect side off
step 5 "luz de baixo muda (teclado arco-íris), lateral deve continuar desligada" bakey effect back wave --speed 2
step 6 "respiração branca"  bakey effect side breathing --color ffffff
step 7 "desligada"          bakey effect side off
say -v Flo "fim do teste"
open -a "BA-KEY Menu"
