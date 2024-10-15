#!/bin/bash
# Осуществляет установку fish shell
sudo apt update && sudo apt upgrade

# Делаем фаил fish_theme.sh исполняемым
chmod +x fish_theme.sh

# Устанавливаем fish
sudo apt install fish

# Устанавливаем fish как дефолтный shell
chsh -s /usr/bin/fish $USERNAME

# Устанавливаем менеджер плагинов omf
curl https://raw.githubusercontent.com/oh-my-fish/oh-my-fish/master/bin/install | fish