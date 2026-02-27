#!/bin/sh
#=================================================
#   System Required: OpenHarmony (M-Robots)
#   Description: M-Robots 补丁一键安装脚本
#   Usage: 将本脚本与 M-Robots_patch 目录放在同一路径下执行
#   Site: https://github.com/NiMobushimo/spark_noetic
#=================================================

# --- 颜色定义 ---
Green_font_prefix="\033[32m"
Red_font_prefix="\033[31m"
Yellow_font_prefix="\033[1;33m"
Blue_font_prefix="\033[0;34m"
Font_color_suffix="\033[0m"

Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Warn="${Yellow_font_prefix}[警告]${Font_color_suffix}"
Tip="${Green_font_prefix}[注意]${Font_color_suffix}"
OK="${Green_font_prefix}[  OK  ]${Font_color_suffix}"
FAIL="${Red_font_prefix}[ FAIL ]${Font_color_suffix}"
Separator="——————————————————————————————————————————————"

# --- 路径定义 ---
# 补丁目录（与本脚本同级的 M-Robots_patch 文件夹）
PATCH_DIR="$(cd "$(dirname "$0")" && pwd)/M-Robots_patch"
# 开发板 ROS 根目录
RELEASE_DIR="/data/local/release"
# 开发板服务配置目录
INIT_DIR="/etc/init"
# 开发板脚本目录
LOCAL_DIR="/data/local"

# --- 统计 ---
TOTAL=0
SUCCESS=0
FAILED=0

# =================================================
# 工具函数
# =================================================

# 安全复制文件（自动创建目标目录）
safe_copy() {
    src="$1"
    dst="$2"
    TOTAL=$((TOTAL + 1))
    dst_dir=$(run busybox dirname "$dst")
    if [ ! -d "$dst_dir" ]; then
        mkdir -p "$dst_dir" 2>/dev/null
    fi
    if cp -f "$src" "$dst" 2>/dev/null; then
        printf "  ${OK} %s\n" "$dst"
        SUCCESS=$((SUCCESS + 1))
    else
        printf "  ${FAIL} %s\n" "$dst"
        FAILED=$((FAILED + 1))
    fi
}

# 安全复制整个目录（递归）
safe_copy_dir() {
    src_dir="$1"
    dst_dir="$2"
    if [ ! -d "$src_dir" ]; then
        printf "  ${Warn} 源目录不存在，跳过: %s\n" "$src_dir"
        return
    fi
    mkdir -p "$dst_dir" 2>/dev/null
    # 遍历源目录所有文件
    find "$src_dir" -type f | while read -r src_file; do
        rel_path="${src_file#$src_dir/}"
        dst_file="$dst_dir/$rel_path"
        safe_copy "$src_file" "$dst_file"
    done
}

# =================================================
# 检查环境
# =================================================

check_env() {
    printf "${Separator}\n"
    printf "${Info} 正在检查运行环境...\n"
    printf "${Separator}\n"

    # 检查补丁目录
    if [ ! -d "$PATCH_DIR" ]; then
        printf "${Error} 未找到补丁目录: %s\n" "$PATCH_DIR"
        printf "${Error} 请确保 M-Robots_patch 文件夹与本脚本在同一目录下！\n"
        exit 1
    fi
    printf "${Info} 补丁目录: ${Green_font_prefix}%s${Font_color_suffix}\n" "$PATCH_DIR"

    # 检查目标路径
    if [ ! -d "$RELEASE_DIR" ]; then
        printf "${Error} 未找到 ROS 目录: %s\n" "$RELEASE_DIR"
        printf "${Error} 请确认开发板 ROS 环境已正确安装！\n"
        exit 1
    fi
    printf "${Info} ROS 目录: ${Green_font_prefix}%s${Font_color_suffix}\n" "$RELEASE_DIR"

    # 检查文件系统是否可写
    if ! touch "$RELEASE_DIR/.write_test" > /dev/null 2>&1; then
        printf "${Warn} 文件系统为只读，正在重新挂载...\n"
        mount -o remount,rw /
        if ! touch "$RELEASE_DIR/.write_test" > /dev/null 2>&1; then
            printf "${Error} 挂载失败！请手动执行: mount -o remount,rw /\n"
            exit 1
        fi
    fi
    rm -f "$RELEASE_DIR/.write_test"
    printf "${Info} 文件系统可写，继续安装。\n"
    printf "${Separator}\n"
}

# =================================================
# 安装步骤
# =================================================

# 步骤1：安装 cfg 配置文件（SSH 和 USB 串口自启服务）
install_cfg() {
    printf "\n${Info} [步骤 1/7] 安装开机自启服务配置文件...\n"

    # SSH 开机自启脚本 -> /data/local/ssh_poweron.sh
    safe_copy "$PATCH_DIR/cfg/ssh_poweron.sh" "$LOCAL_DIR/ssh_poweron.sh"
    chmod +x "$LOCAL_DIR/ssh_poweron.sh" 2>/dev/null

    # SSH 服务配置 -> /etc/init/ssh_start_service.cfg
    mkdir -p "$INIT_DIR" 2>/dev/null
    safe_copy "$PATCH_DIR/cfg/ssh_start_service.cfg" "$INIT_DIR/ssh_start_service.cfg"

    # USB 串口软链接守护脚本 -> /data/local/usbRules.sh
    safe_copy "$PATCH_DIR/cfg/usbRules.sh" "$LOCAL_DIR/usbRules.sh"
    chmod +x "$LOCAL_DIR/usbRules.sh" 2>/dev/null

    # USB 串口服务配置 -> /etc/init/usb_rules_service.cfg
    safe_copy "$PATCH_DIR/cfg/usb_rules_service.cfg" "$INIT_DIR/usb_rules_service.cfg"
}

# 步骤2：安装 include 头文件
install_include() {
    printf "\n${Info} [步骤 2/7] 安装 C++ 头文件 (swiftpro)...\n"
    safe_copy_dir "$PATCH_DIR/include" "$RELEASE_DIR/usr/include"
}

# 步骤3：安装 lib 库文件和 Python 节点
install_lib() {
    printf "\n${Info} [步骤 3/7] 安装库文件和 Python 节点...\n"

    # libcereal_port.so -> /data/local/release/usr/lib/
    safe_copy "$PATCH_DIR/lib/libcereal_port.so" "$RELEASE_DIR/usr/lib/libcereal_port.so"

    # swiftpro 可执行节点 -> /data/local/release/usr/lib/swiftpro/
    safe_copy_dir "$PATCH_DIR/lib/swiftpro" "$RELEASE_DIR/usr/lib/swiftpro"

    # spark_carry_object Python 节点和 rviz 配置
    # -> /data/local/release/usr/lib/spark_carry_object/
    safe_copy "$PATCH_DIR/lib/spark_carry_object/cali_cam_cv3.py" \
        "$RELEASE_DIR/usr/lib/spark_carry_object/cali_cam_cv3.py"
    safe_copy "$PATCH_DIR/lib/spark_carry_object/cali_pos.py" \
        "$RELEASE_DIR/usr/lib/spark_carry_object/cali_pos.py"
    safe_copy "$PATCH_DIR/lib/spark_carry_object/s_carry_object_cv3.py" \
        "$RELEASE_DIR/usr/lib/spark_carry_object/s_carry_object_cv3.py"
    safe_copy_dir "$PATCH_DIR/lib/spark_carry_object/rviz" \
        "$RELEASE_DIR/usr/lib/spark_carry_object/rviz"

    # 赋予 Python 脚本可执行权限
    chmod +x "$RELEASE_DIR/usr/lib/spark_carry_object/"*.py 2>/dev/null && \
        printf "  ${OK} spark_carry_object/*.py 已赋予可执行权限\n"

    # 软链接 python3（手眼标定和物品抓取需要）
    if [ ! -f "/usr/bin/python3" ]; then
        ln -sf "$RELEASE_DIR/bin/python3" /usr/bin/python3 2>/dev/null && \
            printf "  ${OK} 已创建 python3 软链接: /usr/bin/python3\n" || \
            printf "  ${Warn} python3 软链接创建失败，请手动执行: ln -sf %s/bin/python3 /usr/bin/python3\n" "$RELEASE_DIR"
    else
        printf "  ${Tip} /usr/bin/python3 已存在，跳过软链接创建。\n"
    fi
}

# 步骤4：安装 share 中的 launch 文件和 rviz 配置
install_share() {
    printf "\n${Info} [步骤 4/7] 安装 ROS 包 launch 文件和 rviz 配置...\n"

    # --- 驱动相关 ---
    printf "  ${Blue_font_prefix}>> 驱动 launch 文件${Font_color_suffix}\n"
    safe_copy_dir "$PATCH_DIR/share/lidar_driver_transfer" \
        "$RELEASE_DIR/usr/share/lidar_driver_transfer"
    safe_copy_dir "$PATCH_DIR/share/camera_driver_transfer" \
        "$RELEASE_DIR/usr/share/camera_driver_transfer"
    safe_copy_dir "$PATCH_DIR/share/ydlidar_ros_driver" \
        "$RELEASE_DIR/usr/share/ydlidar_ros_driver"
    safe_copy_dir "$PATCH_DIR/share/ydlidar_g2" \
        "$RELEASE_DIR/usr/share/ydlidar_g2"

    # --- 底盘控制 ---
    printf "  ${Blue_font_prefix}>> 底盘控制 (spark_teleop)${Font_color_suffix}\n"
    safe_copy_dir "$PATCH_DIR/share/spark_teleop" \
        "$RELEASE_DIR/usr/share/spark_teleop"

    # --- 建图 ---
    printf "  ${Blue_font_prefix}>> 激光雷达建图 (spark_slam)${Font_color_suffix}\n"
    safe_copy_dir "$PATCH_DIR/share/spark_slam" \
        "$RELEASE_DIR/usr/share/spark_slam"

    printf "  ${Blue_font_prefix}>> 地图保存 (map_server)${Font_color_suffix}\n"
    safe_copy_dir "$PATCH_DIR/share/map_server" \
        "$RELEASE_DIR/usr/share/map_server"

    printf "  ${Blue_font_prefix}>> 深度摄像头建图 (spark_rtabmap)${Font_color_suffix}\n"
    safe_copy_dir "$PATCH_DIR/share/spark_rtabmap" \
        "$RELEASE_DIR/usr/share/spark_rtabmap"

    # --- 导航 ---
    printf "  ${Blue_font_prefix}>> 导航 (spark_navigation)${Font_color_suffix}\n"
    safe_copy_dir "$PATCH_DIR/share/spark_navigation" \
        "$RELEASE_DIR/usr/share/spark_navigation"

    # --- 深度跟随 ---
    printf "  ${Blue_font_prefix}>> 深度跟随 (spark_follower)${Font_color_suffix}\n"
    safe_copy_dir "$PATCH_DIR/share/spark_follower" \
        "$RELEASE_DIR/usr/share/spark_follower"

    # --- 手眼标定 & 物品抓取 ---
    printf "  ${Blue_font_prefix}>> 手眼标定 & 物品抓取 (spark_carry_object)${Font_color_suffix}\n"
    safe_copy_dir "$PATCH_DIR/share/spark_carry_object" \
        "$RELEASE_DIR/usr/share/spark_carry_object"

    # --- 机械臂 ---
    printf "  ${Blue_font_prefix}>> 机械臂 (swiftpro / swift_moveit_config)${Font_color_suffix}\n"
    safe_copy_dir "$PATCH_DIR/share/swiftpro" \
        "$RELEASE_DIR/usr/share/swiftpro"
    safe_copy_dir "$PATCH_DIR/share/swift_moveit_config" \
        "$RELEASE_DIR/usr/share/swift_moveit_config"

    # --- 深度学习 (YOLO) ---
    printf "  ${Blue_font_prefix}>> 深度学习 (darknet_ros / tensorflow_object_detector)${Font_color_suffix}\n"
    safe_copy_dir "$PATCH_DIR/share/darknet_ros" \
        "$RELEASE_DIR/usr/share/darknet_ros"
    safe_copy_dir "$PATCH_DIR/share/tensorflow_object_detector" \
        "$RELEASE_DIR/usr/share/tensorflow_object_detector"
}

# 步骤5：安装一键启动脚本 onekey.sh
install_onekey() {
    printf "\n${Info} [步骤 5/7] 安装一键启动脚本 (onekey.sh)...\n"
    if [ -f "$PATCH_DIR/onekey.sh" ]; then
        safe_copy "$PATCH_DIR/onekey.sh" "$RELEASE_DIR/onekey.sh"
        chmod +x "$RELEASE_DIR/onekey.sh" 2>/dev/null && \
            printf "  ${OK} onekey.sh 已赋予可执行权限\n"
    else
        printf "  ${Warn} 补丁中未找到 onekey.sh，跳过。\n"
    fi
}

# 步骤6：创建地图保存目录
install_map_dir() {
    printf "\n${Info} [步骤 6/7] 创建地图保存目录...\n"
    MAP_SCRIPTS_DIR="$RELEASE_DIR/usr/share/spark_slam/scripts"
    if mkdir -p "$MAP_SCRIPTS_DIR" 2>/dev/null; then
        printf "  ${OK} 地图保存目录已就绪: %s\n" "$MAP_SCRIPTS_DIR"
    else
        printf "  ${Warn} 地图保存目录创建失败，请手动执行: mkdir -p %s\n" "$MAP_SCRIPTS_DIR"
    fi
}

# 步骤7：安装后验证
post_check() {
    printf "\n${Info} [步骤 7/7] 安装后关键文件验证...\n"

    check_file() {
        if [ -f "$1" ]; then
            printf "  ${OK} %s\n" "$1"
        else
            printf "  ${FAIL} 缺失: %s\n" "$1"
        fi
    }

    check_file "$LOCAL_DIR/ssh_poweron.sh"
    check_file "$LOCAL_DIR/usbRules.sh"
    check_file "$INIT_DIR/ssh_start_service.cfg"
    check_file "$INIT_DIR/usb_rules_service.cfg"
    check_file "$RELEASE_DIR/usr/lib/libcereal_port.so"
    check_file "$RELEASE_DIR/usr/lib/spark_carry_object/cali_cam_cv3.py"
    check_file "$RELEASE_DIR/usr/lib/spark_carry_object/s_carry_object_cv3.py"
    check_file "$RELEASE_DIR/usr/share/ydlidar_ros_driver/launch/G6_G7.launch"
    check_file "$RELEASE_DIR/usr/share/spark_teleop/launch/teleop.launch"
    check_file "$RELEASE_DIR/usr/share/spark_slam/launch/2d_slam_teleop.launch"
    check_file "$RELEASE_DIR/usr/share/spark_rtabmap/launch/spark_rtabmap_teleop.launch"
    check_file "$RELEASE_DIR/usr/share/spark_navigation/launch/amcl_demo_lidar_rviz.launch"
    check_file "$RELEASE_DIR/usr/share/spark_follower/launch/bringup.launch"
    check_file "$RELEASE_DIR/usr/share/spark_carry_object/launch/spark_carry_object_only_cv3.launch"
    check_file "$RELEASE_DIR/usr/share/darknet_ros/launch/deeplearn_darknet_yoloV3.launch"
    check_file "$RELEASE_DIR/usr/share/map_server/map_server.launch"
    check_file "$RELEASE_DIR/onekey.sh"
}

# =================================================
# 主流程
# =================================================

printf "\n"
printf "${Separator}\n"
printf "  M-Robots 补丁安装脚本\n"
printf "  目标路径: %s\n" "$RELEASE_DIR"
printf "${Separator}\n"
printf "\n"
printf "${Warn} 本脚本将覆盖开发板上的相关文件，请确认已备份重要数据。\n"
printf "按回车键（Enter）开始安装，或按 Ctrl+C 取消: "
read _dummy

check_env
install_cfg
install_include
install_lib
install_share
install_onekey
install_map_dir
post_check

printf "\n"
printf "${Separator}\n"
printf "${Info} 安装完成！共处理 ${Yellow_font_prefix}%d${Font_color_suffix} 个文件，" "$TOTAL"
printf "成功 ${Green_font_prefix}%d${Font_color_suffix} 个，" "$SUCCESS"
printf "失败 ${Red_font_prefix}%d${Font_color_suffix} 个。\n" "$FAILED"
printf "${Separator}\n"

if [ "$FAILED" -gt 0 ]; then
    printf "${Warn} 有 %d 个文件安装失败，请检查上方 ${Red_font_prefix}[ FAIL ]${Font_color_suffix} 条目。\n" "$FAILED"
fi

printf "\n"
printf "${Tip} 后续手动操作提示：\n"
printf "${Tip}   1. 如需 SSH 开机自启，请确认 /etc/selinux/config 中 SELINUX=permissive 或 disabled\n"
printf "${Tip}   2. 如需 SSH 密码登录，请先执行: echo \"root:123456\" | run busybox chpasswd\n"
printf "${Tip}   3. 如需生成 SSH 密钥，请执行: run ssh-keygen -t rsa -f /usr/etc/ssh_host_rsa_key -N ''\n"
printf "${Tip}   4. YOLOv3 权重文件 (yolov3.weights) 需单独下载，放至:\n"
printf "${Tip}      %s/usr/share/darknet_ros/yolo_network_config/weights/\n" "$RELEASE_DIR"
printf "${Tip}   5. 安装完成后建议重启开发板以使服务配置生效\n"
printf "\n"
