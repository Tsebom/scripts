#!/bin/bash
# Осуществляет установку fish shell

set -e # Прерывать выполнение при ошибках

#--------------------VARIABLES----------------------------

RED='\033[0;31m' # ANSI код для красного
GREEN='\033[0;32m' # ANSI код для зеленого
NC='\033[0m' # Сброс цвета (No Color)

# Получаем последнюю версию NVM
NVM_VERSION=$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep tag_name | head -1 | sed -E 's/.*"([^"]+)".*/\1/')

#----------------------FISH-------------------------------

sudo apt update
sudo apt install -y fish curl tmux fzf

FISH_PATH=$(which fish)

if ! grep -q "^$FISH_PATH$" /etc/shells; then
    echo "Add $FISH_PATH в /etc/shells..."
    echo "$FISH_PATH" | sudo tee -a /etc/shells
fi

# Устанавливаем fish как дефолтный shell
chsh -s "$FISH_PATH" "$(whoami)"

# Устанавливаем менеджер плагинов omf
curl -L https://get.oh-my.fish | fish

# Устанавливаем плагины
fish -c "omf install https://github.com/PatrickF1/fzf.fish" # для удобного поиска команд

# Устанавливаем тему
fish -c "omf install https://github.com/soerdev/soerfish" # soer
fish -c "omf theme soer"

# Настраиваем тему
mkdir -p $HOME/.config/fish/conf.d/
cat <<EOF >> "$HOME/.config/fish/conf.d/omf.fish"

set -g theme_display_first_line yes
set -g theme_display_node yes
set -g theme_display_version_info yes

EOF

#----------------------EXA--------------------------------

# Устанавливаем exa
wget https://github.com/ogham/exa/releases/download/v0.10.1/exa-linux-x86_64-v0.10.1.zip
unzip exa-linux-x86_64-v0.10.1.zip
sudo cp exa-linux-x86_64-v0.10.1/bin/exa /usr/local/bin/
cp exa-linux-x86_64-v0.10.1/completions/exa.fish $HOME/.config/fish/conf.d/

# Удаляем скачанный архив и распакованную папку
rm exa-linux-x86_64-v0.10.1.zip
rm -rf exa-linux-x86_64-v0.10.1

#---------------------NODEJS------------------------------

# Устанавливаем NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh | bash

# Проверяем, что nvm установлен
if ! command -v nvm &> /dev/null; then
    echo "${RED}Warning: NVM is not installed.${NC}"
    exit 1
fi

# Устанавливаем последнюю LTS версию Node.js
nvm install --lts
nvm use --lts
nvm alias default 'lts/*'

# Выводим версии
echo "${GREEN}Nodejs installation complete:${NC}"
echo "Node.js: $(node -v)"
echo "npm: $(npm -v)"

#---------------------TMUX--------------------------------

cp confing/tmux/.tmux.conf ~/.tmux.conf

#---------------------ALIASES-----------------------------

cat <<EOF >> "$HOME/.config/fish/config.fish"

# Custom aliases
alias af 'nano \$HOME/.config/fish/config.fish'
alias lr 'exa -lah --icons --tree'
alias ll 'exa -lah --icons'
alias t 'tmux'
alias leyout 'git clone https://github.com/Tsebom/gulp-start'

EOF
