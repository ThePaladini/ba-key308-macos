<p align="center"><img src="Resources/AppIcon-1024.png" width="140" alt="Ícone do BA-KEY Menu"></p>

<h1 align="center">BA-KEY Menu</h1>

<p align="center">
<a href="README.md">English</a> · <b>Português (Brasil)</b>
</p>

<p align="center">
App de barra de menus e linha de comando para macOS, feito para o teclado <b>Basike BA-KEY308</b>,<br>
um teclado da plataforma <b>Dareu TK51G</b> (USB VID <code>0x260D</code>, PID <code>0x0130</code>) cujo software oficial só existe para Windows.
</p>

<p align="center">
<a href="https://github.com/ThePaladini/ba-key308-macos/releases/latest"><b>Baixar</b></a> ·
<a href="docs/PROTOCOL.md">Protocolo</a> ·
<a href="docs/REVERSE-ENGINEERING.md">Como foi feita a engenharia reversa</a> ·
<a href="#outros-teclados-dareu">Outros teclados Dareu</a>
</p>

<p align="center">
<a href="https://www.youtube.com/shorts/MuPTBXvzvFQ"><img src="https://img.youtube.com/vi/MuPTBXvzvFQ/hqdefault.jpg" width="320" alt="Vídeo de demonstração"></a><br>
<sub>▶ <a href="https://www.youtube.com/shorts/MuPTBXvzvFQ">Vídeo de demonstração</a> (35 s) · <a href="https://www.youtube.com/shorts/qZohvX95IrM">English version</a></sub>
</p>

---

Recuperamos o protocolo descompilando o app oficial de configuração para Windows. Este app conversa
com o teclado usando esse mesmo protocolo, por **Bluetooth, cabo USB ou receptor 2.4G**. Não precisa
de drivers nem de extensões de kernel, não usa o código do Windows e não fica nada rodando em segundo
plano, a não ser que você escolha um efeito desenhado pelo Mac.

> **Não oficial.** Não tem nenhuma ligação com a Basike nem com a Dareu. O app só envia comandos de uma
> lista revisada (iluminação e perfis). Comandos de atualização de firmware e de gravação na memória
> flash não podem ser enviados. Veja [docs/SAFETY.md](docs/SAFETY.md) (em inglês). Use por sua conta e risco.

## Teclados compatíveis

Todos são o mesmo projeto de referência da Dareu, chamado internamente de **TK51G**, vendido com marcas diferentes.

| Teclado | Layout | USB PID (VID `0x260D`) | Situação |
|---|---|---|---|
| **Basike BA-KEY308** | ABNT2 | `0x0130` | ✅ testado (Bluetooth, USB); mapa de LEDs por tecla calibrado |
| **Dareu EK75** | ANSI | `0x0101`, `0x0045` | 🧪 experimental: reconhecido, ainda não testado; mapa de LEDs deduzido |
| **Husky Nomadic HTG200 / HTG500 / HTG800 V2** (Kabum) | ANSI | `0x0101` | 🧪 experimental (mesmo hardware do EK75) |
| Receptor 2.4G dos modelos acima | — | `0x0042` | implementado, ainda não testado |
| Outros teclados Dareu com o mesmo protocolo (`FwType 0`): Z82 / Z82 PRO, A98, FK98, A87 PRO, EK87 PRO, A104, EK106 PRO, EK81 MAX, COOL 98, DK87 PRO, DK108 PRO, EK815 MAX, FLEX 75 | vários | ver [catálogo](docs/DAREU-CATALOG.md) | ❔ efeitos provavelmente funcionam; o app ainda não os reconhece; o `bakey info` detecta, mande um relato |
| Revisões novas do EK75, CK75 PRO, teclados magnéticos "HE/RT" (`FwType` ≠ 0) | | | ❌ protocolo diferente |

A lista completa vem do catálogo público do driver web da Dareu, consultado para este projeto:
[docs/DAREU-CATALOG.md](docs/DAREU-CATALOG.md) (em inglês). Como sabemos que é a mesma plataforma: o catálogo público do driver web da Dareu lista os PIDs `0x0101` e
`0x0045` como `"Model": "TK51G"`, e o Husky Nomadic é documentado pelo
[open-ek75](https://github.com/mateusands/open-ek75) como um EK75 com outra marca. **Tem um desses, ou
outro teclado `0x260D`?** Mande um
[relato de compatibilidade](https://github.com/ThePaladini/ba-key308-macos/issues/new?template=compatibility-report.yml).
O comando `bakey info` usado no relato só lê, não altera nada.

## Recursos

- **Painel na barra de menus**
  - Tipo de conexão, versão do firmware e nível da bateria (que também pode aparecer na barra de menus).
  - **Iluminação das teclas**: os 19 efeitos do próprio teclado, com cor (amostras, seletor de cores
    ou o arco-íris do firmware), direção, brilho e um controle de velocidade que cobre toda a faixa do
    firmware, de 1 a 255 (o app oficial só usa de 1 a 3).
  - **Efeitos do Mac**: efeitos desenhados pelo Mac, com controle total de velocidade:
    - **Gota de chuva ao apertar uma tecla**: uma onda se espalha a partir da tecla que você aperta.
    - Chuva aleatória, Onda e Respiração.
  - **Luz lateral**: desligada, fixa ou respiração, com cor e brilho.
  - Abrir ao iniciar sessão.
- **Pintor de teclas**: clique ou arraste para colorir cada tecla. Tem conta-gotas, preenchimento,
  layouts prontos (WASD, setas, arco-íris…) e layouts salvos. As cores são reenviadas quando o teclado
  reconecta.
- **Linha de comando `bakey`**: `bakey showcase` (show de luzes cronometrado para filmar), `bakey info`, `bakey effect back wave --speed 3`,
  `bakey keys W=ff0000 A=ff0000 …`, consultas brutas só de leitura, testes de velocidade.

Os efeitos do teclado ficam **gravados no próprio teclado** e continuam funcionando em qualquer
computador, mesmo sem o app.

## Instalação

1. Baixe o `BA-KEY-Menu-x.y.z.zip` da [versão mais recente](https://github.com/ThePaladini/ba-key308-macos/releases/latest)
   e descompacte.
2. Mova o **BA-KEY Menu.app** para **Aplicativos** (/Applications).
3. O app não é notarizado pela Apple, então a primeira abertura precisa de um passo extra. Clique com
   o botão direito no app → **Abrir** → **Abrir**. Se o macOS não oferecer o botão Abrir, vá em
   Ajustes do Sistema → Privacidade e Segurança → **Abrir Mesmo Assim**, ou rode no Terminal:
   ```bash
   xattr -dr com.apple.quarantine "/Applications/BA-KEY Menu.app"
   ```
4. Um ícone de teclado aparece na barra de menus (o app não aparece no Dock). Marque **Launch at
   login** se quiser que ele abra sempre com o Mac.

Opcional: a linha de comando vem na mesma versão (`bakey-x.y.z.zip`). Coloque o `bakey` em alguma pasta
do seu `PATH`.

**Permissões:** só o efeito *Raindrop (Mac, on key press)* precisa de **Monitoramento de Entrada**,
porque ele precisa saber qual tecla você apertou. O app pede a permissão na primeira vez que você
escolhe o efeito. As teclas servem só para posicionar a onda e não são gravadas nem armazenadas.

Requer macOS 13 Ventura ou mais recente, em Mac com Apple Silicon ou Intel. Testado no macOS 26.

> A interface do app está em inglês. Os nomes abaixo são os que aparecem no menu.

## Qual efeito usar?

| Você quer | Use | Funciona por |
|---|---|---|
| Uma gota de chuva lenta, em qualquer lugar | **Area Reactive** (efeito do teclado) com a velocidade toda à esquerda | qualquer conexão, sem precisar do app |
| Um efeito do teclado mais rápido do que o app oficial permite | Efeito do teclado + velocidade para a direita | qualquer conexão |
| Ondas a cada tecla, em qualquer velocidade | **Raindrop (Mac, on key press)** | suave no USB; usável no Bluetooth com velocidade baixa |
| Onda ou Respiração desenhadas pelo Mac | Mac effects | suave no USB; cerca de 6 atualizações/s no Bluetooth |
| Cores próprias em cada tecla | **Paint individual keys…** | qualquer conexão |

Por que o Bluetooth é mais lento para os efeitos do Mac? Cada pacote de iluminação espera um "encontro"
da conexão Bluetooth, que leva cerca de 154 ms neste teclado, contra cerca de 1 ms no USB. O app
contorna isso enviando só as fileiras do teclado que mudaram. Os detalhes estão em
[docs/BLUETOOTH.md](docs/BLUETOOTH.md) (em inglês).

## Bom saber

- **A iluminação apaga sozinha** depois de 3 minutos sem uso. Qualquer tecla acende de novo.
- **Karabiner-Elements:** ele "toma conta" do teclado no USB. Nesse caso os efeitos que reagem às
  teclas usam os eventos de teclado do macOS, e o teclado do MacBook também gera ondas. No Bluetooth
  isso não acontece.
- **Para desinstalar:** feche o app, apague `/Applications/BA-KEY Menu.app` (e o `bakey`, se tiver
  instalado) e, se quiser, o certificado "BA-KEY Menu Dev" no Acesso às Chaves.

## Compilar a partir do código

```bash
git clone https://github.com/ThePaladini/ba-key308-macos.git
cd ba-key308-macos
scripts/make-dev-cert.sh          # opcional, uma vez: assinatura local estável, para o macOS lembrar as permissões entre builds
scripts/build-app.sh --install    # compila (universal), instala em /Applications e o `bakey` em ~/.local/bin, e abre o app
```

Desenvolvimento:

```bash
swift build          # build de depuração
swift test           # testes (não precisa do teclado)
swift run bakey info # linha de comando com o teclado conectado
```

Requer o Xcode ou as Command Line Tools (Swift 5.9+).

## Outros teclados Dareu

O BA-KEY308 é um projeto **Dareu "TK51G"** (código de modelo `TK51G_0130`) vendido com a marca brasileira Basike.
O protocolo está na `DeviceBase.dll`, compartilhada pelos apps Windows da Dareu em vários produtos.
Outros teclados baseados em Dareu (`VID 0x260D`) muito provavelmente usam o mesmo protocolo, só mudando
o PID, a tabela de teclas e a matriz de LEDs.

Para adaptar este projeto:

1. Confira se o teclado tem um relatório de 64 bytes:
   `ioreg -r -c IOHIDDevice -l | grep -A40 '"VendorID" = 9741'` deve mostrar `MaxFeatureReportSize = 65`.
2. Mude `BAKey.keyboardPID` em `Sources/BAKeyCore/Protocol.swift` e rode `bakey info`. Comandos de
   leitura (GET) são seguros.
3. Extraia a tabela de teclas do `Products/*.dll` do seu modelo com os scripts em [`tools/`](tools/) e
   **calibre a matriz de LEDs com quadros de teste**. A tabela do próprio app Windows estava errada
   para este modelo. Veja [docs/KEY-MATRIX.md](docs/KEY-MATRIX.md).

O método completo está em [docs/REVERSE-ENGINEERING.md](docs/REVERSE-ENGINEERING.md). Pull requests
para outros modelos são bem-vindos.

## Documentação (em inglês)

| Documento | Conteúdo |
|---|---|
| [PROTOCOL.md](docs/PROTOCOL.md) | O protocolo HID: formato dos pacotes, handshake, todas as classes de comando, exemplos capturados |
| [KEY-MATRIX.md](docs/KEY-MATRIX.md) | IDs das teclas e a matriz de LEDs calibrada |
| [BLUETOOTH.md](docs/BLUETOOTH.md) | Por que o Bluetooth é lento para iluminação, os experimentos e a solução |
| [SOFT-EFFECTS.md](docs/SOFT-EFFECTS.md) | Efeitos do Mac, a investigação sobre a velocidade da gota de chuva original, como criar um efeito |
| [DAREU-CATALOG.md](docs/DAREU-CATALOG.md) | Todos os produtos do catálogo público da Dareu: plataforma, tipo de firmware e o que isso significa para compatibilidade |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Organização do código e decisões de projeto |
| [SAFETY.md](docs/SAFETY.md) | Comandos que podem inutilizar o teclado e como o projeto os bloqueia |
| [REVERSE-ENGINEERING.md](docs/REVERSE-ENGINEERING.md) | Passo a passo de como o protocolo foi recuperado |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Problemas comuns |
| [CHANGELOG.md](CHANGELOG.md) | Notas de versão |

## Situação

| | |
|---|---|
| Bluetooth LE | ✅ testado |
| Cabo USB | ✅ testado (cerca de 130× mais rápido que o Bluetooth para iluminação) |
| Receptor 2.4G | implementado a partir do código do Windows, **ainda não testado** |
| Dareu EK75 / Husky Nomadic | reconhecidos desde a v1.1.0, **ainda não testados** |
| Efeitos, cor, velocidade, brilho, luz lateral | ✅ |
| Cores por tecla, efeitos do Mac, gota de chuva ao apertar | ✅ |
| Bateria, informações do firmware | ✅ |
| Remapear teclas, macros, tempo para apagar | protocolo documentado, ainda não implementado |

## Licença

[MIT](LICENSE). Os nomes e marcas do teclado pertencem aos seus donos. Este repositório não contém
código nem binários do software do fabricante. Os dados do protocolo, as posições das teclas e o mapa
de teclas padrão foram obtidos a partir dele, para fins de interoperabilidade.
