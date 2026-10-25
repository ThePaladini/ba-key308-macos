#!/bin/zsh
# Reproduces the 2.4G side-light bug (the side light comes back on after the keyboard wakes) and tries three
# ways to turn it off again. Each step is announced aloud; note after which step the side light went OFF.
export PATH=$HOME/.local/bin:$PATH
LOG=${1:-/tmp/sidelight-wake-test.log}
V=Flo
osascript -e 'quit app "BA-KEY Menu"' 2>/dev/null; sleep 1
: > $LOG
info() { bakey info 2>&1 | grep -E '^Side light|Sleeps|Never' | tr '\n' ' '; }
before=$(bakey sleep 2>&1)
echo "before: $before | $(info)" | tee -a $LOG
bakey effect side off >/dev/null              # start from a known state: Off, speed 2
bakey sleep 1 >/dev/null
say -v $V "Deixe o teclado parado. Ele vai dormir em um minuto."
until ! bakey info >/dev/null 2>&1; do sleep 5; done
echo "asleep at $(date +%T)" | tee -a $LOG
say -v $V "Dormiu. Aperte uma tecla e olhe a luz lateral."
until bakey info >/dev/null 2>&1; do sleep 1; done
sleep 2
echo "awake: $(info)" | tee -a $LOG
say -v $V "Acordou. A luz lateral está acesa?"
sleep 4
say -v $V "passo um";  bakey effect side off >/dev/null;                 sleep 5; echo "1 off (same bytes): $(info)" | tee -a $LOG
say -v $V "passo dois"; bakey effect-raw side 0 0 3 >/dev/null;          sleep 5; echo "2 off speed 3: $(info)" | tee -a $LOG
say -v $V "passo três"; bakey effect side breathing >/dev/null; sleep 1.5; bakey effect side off >/dev/null; sleep 4; echo "3 breathing then off: $(info)" | tee -a $LOG
case $before in
  *Never*) bakey sleep never >/dev/null;;
  *"after "*) m=${${before#*after }%% min*}; bakey sleep $m >/dev/null;;
esac
echo "restored: $(bakey sleep 2>&1)" | tee -a $LOG
say -v $V "Fim do teste."
open -a "BA-KEY Menu"
