#!/usr/bin/fish
# Устанвливаем тему soerfish

#  Устанавливаем тему для fish от soer
omf install https://github.com/soerdev/soerfish
omf theme soerfish # Подклчаем тему soerfish

echo " " >> ~/.config/fish/conf.d/omf.fish
echo "set -g theme_display_first_line yes" >> ~/.config/fish/conf.d/omf.fish
echo "set -g theme_display_node yes" >> ~/.config/fish/conf.d/omf.fish
echo "set -g theme_display_version_info yes" >> ~/.config/fish/conf.d/omf.fish