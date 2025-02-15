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
      sed -i '5s/i2c_mcu:.*/i2c_mcu: SB2040/' "$CONFIG_FILE" &&
      sed -i '6s/i2c_bus:.*/i2c_bus: i2c1b/' "$CONFIG_FILE"
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


# 检查指定的配置文件是否存在
if [ ! -f "$CONFIG_DIL" ]; then
    echo "文件不存在: $CONFIG_DIL"
    exit 1
fi

echo "处理文件: $CONFIG_DIL"

# 使用临时文件存储处理后的内容
temp_file=$(mktemp)

# 标志变量，用于跟踪是否已经保留了一个 '[include eddypz.cfg] #eddy配置'
included=0

# 定义需要匹配的包含指令（中文和英文）
include_cn="[include eddypz.cfg] #eddy配置"
include_en="[include eddypz.cfg] #eddy_config"

# 逐行读取配置文件
while IFS= read -r line; do
    if [[ "$line" == "$include_cn" || "$line" == "$include_en" ]]; then
        if [ "$included" -eq 0 ]; then
            echo "$line" >> "$temp_file"
            included=0
        fi
        # 如果已经包含过一次，则跳过后续的包含行
    else
# 如果前一行是包含行且当前行非空，则删除前一个换行符
        if [ "$included" -eq 1 ]; then
            # 检查上一行是否以包含行结尾
            if [ -s "$temp_file" ]; then
                # 获取临时文件的最后一行
                last_line=$(tail -n 1 "$temp_file")
                # 如果最后一行是包含行，则不添加新的换行符
    if [[ "$line" == "$include_cn" || "$line" == "$include_en" ]]; then
                    echo -n "$line" >> "$temp_file"
                else
                    echo "$line" >> "$temp_file"
                fi
            else
                echo "$line" >> "$temp_file"
            fi
        else
            echo "$line" >> "$temp_file"
        fi
        included=1
     fi
done < "$CONFIG_DIL"

# 处理文件末尾可能缺少换行符的情况
if [ -s "$temp_file" ]; then
    last_char=$(tail -c 1 "$temp_file")
    if [ "$last_char" != $'\n' ]; then
        echo "" >> "$temp_file"
    fi
fi

# 将临时文件内容覆盖原文件
mv "$temp_file" "$CONFIG_DIL"

echo "已更新/Updated: $CONFIG_DIL"

echo "配置文件处理完成。/Configuration file processing completed."  