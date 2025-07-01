#!/usr/bin/fish
# Устанвливаем тему soerfish

sudo apt install unzip -y # Устаналиваем распаковщик zip файлов

# Exa плагин для замены ls и tree
wget https://github.com/ogham/exa/releases/download/v0.10.1/exa-linux-x86_64-v0.10.1.zip
mkdir exa
unzip exa-linux-x86_64-v0.10.1.zip -d exa
sudo cp exa/bin/exa /usr/local/bin/
sudo cp completions/exa.fish $HOME/.config/fish/conf.d/
rm exa-linux-x86_64-v0.10.1.zip
rm -R exa-linux-x86_64-v0.10.1

# Add aliases
echo " " >> $HOME/.config/fish/config.fish
echo "# Custom aliases" >> $HOME/.config/fish/config.fish
echo "alias af 'nano $HOME/.config/fish/config.fish'" >> $HOME/.config/fish/config.fish
echo "alias lr 'exa -lah --icons --tree'" >> $HOME/.config/fish/config.fish
echo "alias ll 'exa -lah --icons'" >> $HOME/.config/fish/config.fish
echo "alias leyout 'git clone https://github.com/Tsebom/gulp-start'" >> $HOME/.config/fish/config.fish

# Плагин для удобного поиска команд
omf install https://github.com/PatrickF1/fzf.fish
sudo apt install fzf -y

#  Устанавливаем тему для fish от soer
omf install https://github.com/soerdev/soerfish
omf theme soerfish # Подклчаем тему soerfish

echo " " >> $HOME/.config/fish/conf.d/omf.fish
echo "set -g theme_display_first_line yes" >> $HOME/.config/fish/conf.d/omf.fish
echo "set -g theme_display_node yes" >> $HOME/.config/fish/conf.d/omf.fish
echo "set -g theme_display_version_info yes" >> $HOME/.config/fish/conf.d/omf.fish