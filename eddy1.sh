#!/bin/bash

# ====================================================
# 脚本名称: select_and_run_eddy.sh
# 功能:
#   1. 列出指定父目录下的所有子目录。
#   2. 让用户选择一个子目录。
#   3. 确保选中子目录下的 eddy 脚本具有可执行权限。
#   4. 执行该 eddy 脚本。
# 使用方法:
#   chmod +x select_and_run_eddy.sh
#   ./select_and_run_eddy.sh
# ====================================================

# 获取当前用户的主目录
CURRENT_HOME="$HOME"

# 设置父目录路径
PARENT_DIR="$CURRENT_HOME/Eddy-Automated-Configuration-Script"

CONFIG_FILE="$CURRENT_HOME/printer_data/config/eddypz.cfg"

CONFIG_DIL="$CURRENT_HOME/printer_data/config/printer.cfg"


# 检查脚本是否在当前用户的主目录下运行
if [ "$(pwd)" != "$CURRENT_HOME" ]; then
    echo "错误: 此脚本只能在主目录 '$CURRENT_HOME' 下运行 / Error: This script can only be run in the home directory '$CURRENT_HOME'. " >&2
    exit 1
fi

# 检查父目录是否存在
if [ ! -d "$PARENT_DIR" ]; then
    echo "错误: 父目录 '$PARENT_DIR' 不存在。/ Error: The parent directory '$PARENT_DIR' does not exist." >&2
    exit 1
fi

# 获取所有符合模式的子目录
# 假设子目录名称以 eddy 开头，后面跟随任意字符
SUBDIRS=($(find "$PARENT_DIR" -mindepth 1 -maxdepth 1 -type d -name "eddy*"))

# 检查是否有子目录
if [ ${#SUBDIRS[@]} -eq 0 ]; then
    echo "错误: 在 '$PARENT_DIR' 下未找到任何以 'eddy' 开头的子目录。/ Error: No subdirectories starting with 'eddy' were found under '$PARENT_DIR'." >&2
    exit 1
fi

# 显示子目录列表并让用户选择
echo "下面选择有中英文'eddy'自动化配置文件 / The following options include automated configuration files for 'eddy' in both Chinese and English. ："
for idx in "${!SUBDIRS[@]}"; do
    echo "$((idx + 1))) ${SUBDIRS[idx]##*/}"
done

# 读取用户输入
echo "输入适合自己的配置编号 / Enter the configuration number suitable for yourself"
read -p "输入编号 (1-${#SUBDIRS[@]}) / Enter the number (1-${#SUBDIRS[@]}): " choice

# 验证用户输入
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#SUBDIRS[@]} ]; then
    echo "错误: 无效的选择。/ Error: Invalid selection." >&2
    exit 1
fi

# 获取选中的子目录
SELECTED_DIR="${SUBDIRS[$((choice - 1))]}"

# 设置要执行的脚本路径
SCRIPT_PATH="$SELECTED_DIR/eddy.sh"

# 检查脚本是否存在
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "错误: 在目录 '$SELECTED_DIR' 中未找到 'eddy' 脚本。/ Error: The 'eddy' script was not found in the directory '$SELECTED_DIR'." >&2
    exit 1
fi

# 确保脚本具有可执行权限
if [ ! -x "$SCRIPT_PATH" ]; then
    sudo chmod +x "$SCRIPT_PATH"
    if [ $? -ne 0 ]; then
        echo "错误: 无法为脚本 '$SCRIPT_PATH' 添加可执行权限。/ Error: Unable to add executable permissions to the script '$SCRIPT_PATH'." >&2
        exit 1
    fi
fi

# 执行脚本
echo "正在执行/Under execution. '$SCRIPT_PATH' ..."
"$SCRIPT_PATH"

# 检查脚本执行结果
if [ $? -eq 0 ]; then
    echo "'eddy' 脚本执行成功。/ The 'eddy' script was executed successfully."
else
    echo "'eddy' 脚本执行失败。/ The 'eddy' script execution failed." >&2
    exit 1
fi


# 提示用户确认是否要修改配置文件
read -p "是否是SB2040-V3-PROV3?/Is it SB2040 - V3 - PROV3? (y/n): " choice

case "$choice" in 
  y|Y|Y ) 
    echo "检查配置文件是否存在.../Check whether the configuration file exists..."
    
    # 检查文件是否存在
    if [ -f "$CONFIG_FILE" ]; then
      echo "正在修改配置文件.../Modifying the configuration file..."
      
      # 使用 sed 命令进行修改
      sed -i '4s/i2c_mcu:.*/i2c_mcu: SB2040/' "$CONFIG_FILE" &&
      sed -i '5s/i2c_bus:.*/i2c_bus: i2c1b/' "$CONFIG_FILE"
      sed -i '14s/sensor_pin:.*/sensor_pin:SB2040:gpio28/' "$CONFIG_FILE"
      
      # 检查 sed 命令是否成功
      if [ $? -eq 0 ]; then
        echo "配置文件已成功更新为SB2040 V3-PROV3。/ The configuration file has been successfully updated to SB2040 V3 - PROV3."
        # 用户选择了 yes，继续重启 Klipper 服务
        echo "正在重启 Klipper 服务.../Restarting Klipper service..."
        sudo systemctl restart klipper
        
        # 检查重启是否成功
        if systemctl is-active --quiet klipper; then
          echo "Klipper 服务已成功重启。/The Klipper service has been successfully restarted."
        else
          echo "Klipper 服务重启失败，请检查日志以获取更多信息。/Klipper service restart failed. Please check the log for more information."
          exit 1
        fi
      else
        echo "修改配置文件时出错 / An error occurred when modifying the configuration file."
      fi
    else
      echo "配置文件不存在于 $CONFIG_FILE / The configuration file does not exist in $CONFIG_FILE."
    fi
    ;;
  
  n|N|N )
    echo "不是’SB2040 V3-PROV3‘不重启 Klipper 服务。/ Only the 'SB2040 V3 - PROV3' will restart the Klipper service."
    ;;
  
  * )
    echo "无效的输入。操作已取消。/Invalid input. Operation cancelled."
    ;;
esac

echo "操作已完成./Operation completed."
 
CONFIG_DIR="$HOME/printer_data/config"
CONFIG_FILE="$CONFIG_DIR/printer.cfg"
TMP_FILE="$CONFIG_FILE.tmp"
 
awk -v found=0 '
BEGIN { in_block = 0; expect_next = "" }
 
# 检测完整配置块起始 
/^\[include eddypz.cfg\]/ &&!found { 
    in_block = 1 
    expect_next = "probe"
    block_buffer = $0 "\n" 
    next 
}
 
# 处理预期中的下一行 
in_block && expect_next == "probe" {
    if (/^\[probe_eddy_current fly_eddy_probe\]/) {
        block_buffer = block_buffer $0 "\n"
        expect_next = "z_offset"
    } else {
        # 非完整区块则回退 
        printf "%s", block_buffer 
        in_block = 0 
        print $0 
    }
    next 
}
 
in_block && expect_next == "z_offset" {
    if (/^z_offset:[[:space:]]*0\.5/) {
        block_buffer = block_buffer $0 "\n"
        found = 1  # 标记已找到有效配置 
        printf "%s", block_buffer 
    } else {
        printf "%s", block_buffer 
        print $0 
    }
    in_block = 0 
    next 
}
 
# 跳过重复的完整配置块 
/^\[include eddypz.cfg\]/ && found { 
    skip = 1 
    next 
}
skip && /^\[probe_eddy_current fly_eddy_probe\]/ { next }
skip && /^z_offset:[[:space:]]*0\.5/ { skip = 0; next }
skip { skip = 0; print $0 }
 
# 常规输出 
{ print }
' "$CONFIG_FILE" > "$TMP_FILE"
 
if ! diff -q "$CONFIG_FILE" "$TMP_FILE" >/dev/null; then 
    mv "$TMP_FILE" "$CONFIG_FILE"
    echo "配置文件已更新"
else 
    rm "$TMP_FILE"
    echo "未发现重复配置"
fi