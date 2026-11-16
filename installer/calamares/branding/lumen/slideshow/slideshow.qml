import QtQuick 2.15
import calamares.slideshow 1.0

Presentation {
    id: presentation
    anchors.fill: parent

    Timer {
        id: slideTimer
        interval: 8000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    function onActivate() {
        presentation.currentSlide = 0;
        slideTimer.restart();
    }

    function onLeave() {
        slideTimer.stop();
    }

    // -------------------------------------------------------------
    // Slide 1: Curved Glass Shell
    // -------------------------------------------------------------
    Slide {
        Rectangle {
            anchors.fill: parent
            color: "transparent"

            Rectangle {
                anchors.centerIn: parent
                width: parent.width - 48
                height: parent.height - 48
                radius: 24
                color: "#aa181b22"
                border.color: "#55ffffff"
                border.width: 1.5

                Column {
                    anchors.centerIn: parent
                    width: parent.width - 64
                    spacing: 16

                    Rectangle {
                        width: 140
                        height: 28
                        radius: 14
                        color: "#748dff"
                        Text {
                            anchors.centerIn: parent
                            text: "✦ INTERFACE"
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 11
                            font.letterSpacing: 1.5
                        }
                    }

                    Text {
                        text: "Experiência Visual Curved Glass"
                        color: "#ffffff"
                        font.bold: true
                        font.pixelSize: 24
                    }

                    Text {
                        text: "Elegância translúcida com aceleração nativa na GPU via Wayland Layer-Shell."
                        color: "#cbd5e1"
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }

                    Rectangle { width: parent.width; height: 1; color: "#25ffffff" }

                    Row {
                        spacing: 20
                        Column {
                            spacing: 8
                            Text { text: "• Efeito blur frosted glass dinâmico com bordas especulares"; color: "#e2e8f0"; font.pixelSize: 13 }
                            Text { text: "• Alternância instantânea entre barra lateral e barra horizontal"; color: "#e2e8f0"; font.pixelSize: 13 }
                            Text { text: "• Otimizado para alto contraste e máxima legibilidade para desenvolvedores"; color: "#e2e8f0"; font.pixelSize: 13 }
                        }
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------
    // Slide 2: Hyprland 0.53 Compositor
    // -------------------------------------------------------------
    Slide {
        Rectangle {
            anchors.fill: parent
            color: "transparent"

            Rectangle {
                anchors.centerIn: parent
                width: parent.width - 48
                height: parent.height - 48
                radius: 24
                color: "#aa181b22"
                border.color: "#55ffffff"
                border.width: 1.5

                Column {
                    anchors.centerIn: parent
                    width: parent.width - 64
                    spacing: 16

                    Rectangle {
                        width: 150
                        height: 28
                        radius: 14
                        color: "#8870ff"
                        Text {
                            anchors.centerIn: parent
                            text: "⚡ COMPOSITOR"
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 11
                            font.letterSpacing: 1.5
                        }
                    }

                    Text {
                        text: "Desempenho Extremo com Hyprland 0.53"
                        color: "#ffffff"
                        font.bold: true
                        font.pixelSize: 24
                    }

                    Text {
                        text: "Compositor Wayland moderno com animações suaves e renderização direta."
                        color: "#cbd5e1"
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }

                    Rectangle { width: parent.width; height: 1; color: "#25ffffff" }

                    Row {
                        spacing: 20
                        Column {
                            spacing: 8
                            Text { text: "• Curvas de animação Bezier afinadas (glassCurve 0.22, 1.0, 0.36, 1.0)"; color: "#e2e8f0"; font.pixelSize: 13 }
                            Text { text: "• Suporte nativo a multi-monitor com direct scanout para latência zero"; color: "#e2e8f0"; font.pixelSize: 13 }
                            Text { text: "• Modo de compatibilidade integrado com fallback para Wayfire"; color: "#e2e8f0"; font.pixelSize: 13 }
                        }
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------
    // Slide 3: Dev-First Stack
    // -------------------------------------------------------------
    Slide {
        Rectangle {
            anchors.fill: parent
            color: "transparent"

            Rectangle {
                anchors.centerIn: parent
                width: parent.width - 48
                height: parent.height - 48
                radius: 24
                color: "#aa181b22"
                border.color: "#55ffffff"
                border.width: 1.5

                Column {
                    anchors.centerIn: parent
                    width: parent.width - 64
                    spacing: 16

                    Rectangle {
                        width: 150
                        height: 28
                        radius: 14
                        color: "#748dff"
                        Text {
                            anchors.centerIn: parent
                            text: "⚙ DEV STACK"
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 11
                            font.letterSpacing: 1.5
                        }
                    }

                    Text {
                        text: "Ambiente Completo para Desenvolvedores"
                        color: "#ffffff"
                        font.bold: true
                        font.pixelSize: 24
                    }

                    Text {
                        text: "Configuração instantânea dos melhores editores, terminais e runtimes."
                        color: "#cbd5e1"
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }

                    Rectangle { width: parent.width; height: 1; color: "#25ffffff" }

                    Row {
                        spacing: 20
                        Column {
                            spacing: 8
                            Text { text: "• Terminal Kitty acelerado por GPU com fonte JetBrains Mono Nerd Font"; color: "#e2e8f0"; font.pixelSize: 13 }
                            Text { text: "• Neovim pré-configurado com LSP, Lazy.nvim, Treesitter e Telescope"; color: "#e2e8f0"; font.pixelSize: 13 }
                            Text { text: "• Shell Starship com prompt contextual e multiplexador Tmux afinado"; color: "#e2e8f0"; font.pixelSize: 13 }
                            Text { text: "• Runtimes prontos: Node.js, Python 3, Rust, Go e suporte a Docker"; color: "#e2e8f0"; font.pixelSize: 13 }
                        }
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------
    // Slide 4: System Tuning & Performance
    // -------------------------------------------------------------
    Slide {
        Rectangle {
            anchors.fill: parent
            color: "transparent"

            Rectangle {
                anchors.centerIn: parent
                width: parent.width - 48
                height: parent.height - 48
                radius: 24
                color: "#aa181b22"
                border.color: "#55ffffff"
                border.width: 1.5

                Column {
                    anchors.centerIn: parent
                    width: parent.width - 64
                    spacing: 16

                    Rectangle {
                        width: 160
                        height: 28
                        radius: 14
                        color: "#a970ff"
                        Text {
                            anchors.centerIn: parent
                            text: "🚀 PERFORMANCE"
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 11
                            font.letterSpacing: 1.5
                        }
                    }

                    Text {
                        text: "Ajuste Fino de Sistema & Produtividade"
                        color: "#ffffff"
                        font.bold: true
                        font.pixelSize: 24
                    }

                    Text {
                        text: "Kernel Linux e Ubuntu 26.04 Minimal afinados para compilações pesadas."
                        color: "#cbd5e1"
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }

                    Rectangle { width: parent.width; height: 1; color: "#25ffffff" }

                    Row {
                        spacing: 20
                        Column {
                            spacing: 8
                            Text { text: "• vm.max_map_count (262144) e inotify (524288) para IDEs e contêineres"; color: "#e2e8f0"; font.pixelSize: 13 }
                            Text { text: "• ZRAM configurado com algoritmo zstd para fluidez mesmo com alta carga"; color: "#e2e8f0"; font.pixelSize: 13 }
                            Text { text: "• Snap desabilitado com prioridade total a pacotes nativos Debian (.deb)"; color: "#e2e8f0"; font.pixelSize: 13 }
                            Text { text: "• Assistente Lumen Welcome para pós-instalação no primeiro boot"; color: "#e2e8f0"; font.pixelSize: 13 }
                        }
                    }
                }
            }
        }
    }
}
