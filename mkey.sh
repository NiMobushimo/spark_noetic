#!/bin/sh
#=================================================
#   System Required: OpenHarmony (M-Robots)
#   Description: M-Robots 一键启动管理脚本
#   Based on: spark_noetic / onekey.sh
#   Site: https://github.com/NiMobushimo/spark_noetic
#=================================================

# --- 脚本版本 ---
sh_ver="1.2"

# --- 颜色定义 ---
Green_font_prefix="\033[32m"
Red_font_prefix="\033[31m"
Yellow_font_prefix="\033[1;33m"
Blue_font_prefix="\033[0;34m"
Font_color_suffix="\033[0m"

# --- 消息前缀 ---
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Warn="${Yellow_font_prefix}[警告]${Font_color_suffix}"
Tip="${Green_font_prefix}[注意]${Font_color_suffix}"
Separator="——————————————————————————————————————————————"

# --- 全局变量 ---
CAMERATYPE="d435"
LIDARTYPE="ydlidar_g6"
ARMTYPE="uarm"
DISPLAY_NUM=":0"

# rosdep 在 OpenHarmony 上无法自动识别系统，强制指定为 Ubuntu 20.04
# 否则用到 smach_ros 等包的节点会抛出 OsNotDetected 错误
export ROS_OS_OVERRIDE="ubuntu:20.04"

# =================================================
# 工具函数
# =================================================

# 打印执行命令（高亮显示）
print_command() {
    printf "${Yellow_font_prefix}>>> ${Green_font_prefix}%s${Font_color_suffix}\n" "$1"
}

# 等待用户按回车（OpenHarmony sh 不支持 read -p）
press_enter() {
    printf "%s" "$1"
    read _dummy
}

# 清理并退出（Ctrl+C 或正常退出时调用）
cleanup() {
    printf "\n"
    printf "${Info} 正在停止所有 ROS 节点...\n"
    run busybox killall -9 rosmaster rosout > /dev/null 2>&1
    printf "${Info} 正在关闭虚拟屏幕 (Xvfb) 和 X11VNC 服务...\n"
    # startxvfb 是封装脚本，$! 拿到的是子 shell PID 而非真实 Xvfb 进程。
    # 改用 killall 按进程名安全杀死，确保彻底清理。
    run busybox killall -9 Xvfb > /dev/null 2>&1 && \
        printf "${Info} Xvfb 已关闭。\n" || \
        printf "${Tip} Xvfb 未在运行或已提前退出。\n"
    run busybox killall -9 x11vnc > /dev/null 2>&1 && \
        printf "${Info} X11VNC 已关闭。\n" || \
        printf "${Tip} X11VNC 未在运行或已提前退出。\n"
    printf "${Info} 清理完成，脚本已退出。\n"
    run busybox stty sane 2>/dev/null || true
    exit 0
}

# 捕获 Ctrl+C (INT) 和终止信号 (TERM)
trap cleanup INT TERM

# =================================================
# 环境初始化
# =================================================

# 检查并挂载文件系统（开发板首次启动需要）
check_mount() {
    printf "${Separator}\n"
    printf "${Info} 正在检查文件系统挂载状态...\n"

    # 1. 检查根目录是否可写
    if ! touch /data/local/release/.write_test > /dev/null 2>&1; then
        printf "${Info} 检测到文件系统为只读，正在重新挂载 /...\n"
        mount -o remount,rw /
        if ! touch /data/local/release/.write_test > /dev/null 2>&1; then
            printf "${Error} 根目录挂载失败，请手动执行: mount -o remount,rw /\n"
        else
            rm -f /data/local/release/.write_test
            printf "${Info} 根目录已重新挂载为可写。\n"
        fi
    else
        rm -f /data/local/release/.write_test
        printf "${Info} 根目录已是可写状态。\n"
    fi

    # 2. 确保 /tmp 可写（Xvfb 需要在 /tmp 创建锁文件）
    if ! touch /tmp/.write_test > /dev/null 2>&1; then
        printf "${Info} /tmp 为只读，正在挂载 tmpfs 到 /tmp...\n"
        mount -t tmpfs tmpfs /tmp 2>/dev/null
        if ! touch /tmp/.write_test > /dev/null 2>&1; then
            printf "${Error} /tmp 挂载失败，Xvfb 可能无法启动！请手动执行: mount -t tmpfs tmpfs /tmp\n"
        else
            rm -f /tmp/.write_test
            printf "${Info} tmpfs 已挂载到 /tmp，可写。\n"
        fi
    else
        rm -f /tmp/.write_test
        printf "${Info} /tmp 已是可写状态。\n"
    fi

    # 3. 清理 /tmp 下残留的 Xvfb 锁文件（防止上次异常退出残留）
    if ls /tmp/.tX*-lock > /dev/null 2>&1; then
        printf "${Warn} 检测到 /tmp 中有残留的 Xvfb 锁文件，正在清理...\n"
        rm -f /tmp/.tX*-lock
        rm -rf /tmp/.X*-unix
        printf "${Info} 残留锁文件已清理。\n"
    fi

    printf "${Separator}\n"
}

# 获取本机 IP（使用 busybox ip/ifconfig + cut/grep）
get_local_ip() {
    _ip=""
    # 优先尝试 busybox ip addr
    _ip=$(run busybox ip addr 2>/dev/null \
        | run busybox grep "inet " \
        | run busybox grep -v "127.0.0.1" \
        | run busybox head -1 \
        | run busybox tr -s ' ' \
        | run busybox cut -d' ' -f3 \
        | run busybox cut -d'/' -f1)
    # 备选：busybox ifconfig（旧格式 inet addr:x.x.x.x）
    if [ -z "$_ip" ]; then
        _ip=$(run busybox ifconfig 2>/dev/null \
            | run busybox grep "inet addr" \
            | run busybox grep -v "127.0.0.1" \
            | run busybox head -1 \
            | run busybox cut -d':' -f2 \
            | run busybox cut -d' ' -f1)
    fi
    # 备选：busybox ifconfig（新格式 inet x.x.x.x）
    if [ -z "$_ip" ]; then
        _ip=$(run busybox ifconfig 2>/dev/null \
            | run busybox grep "inet " \
            | run busybox grep -v "127.0.0.1" \
            | run busybox head -1 \
            | run busybox tr -s ' ' \
            | run busybox cut -d' ' -f3)
    fi
    printf "%s" "${_ip:-未知}"
}

# 启动虚拟屏幕和 VNC 服务
start_virtual_screen() {
    printf "${Separator}\n"
    printf "${Info} 正在初始化图形显示环境...\n"
    printf "${Separator}\n"

    # 检查 Xvfb 是否已在运行
    if run busybox pgrep -x "Xvfb" > /dev/null 2>&1; then
        printf "${Tip} 检测到 Xvfb 已在运行，跳过启动。\n"
    else
        printf "${Info} 正在启动 X Virtual Framebuffer (Xvfb)...\n"
        run startxvfb > /dev/null 2>&1 &
        sleep 3
        if run busybox pgrep -x "Xvfb" > /dev/null 2>&1; then
            printf "${Info} Xvfb 已成功启动。\n"
        else
            printf "${Error} Xvfb 启动失败！请检查 /tmp 是否可写，或手动执行: run startxvfb\n"
        fi
    fi

    # 检查 x11vnc 是否已在运行
    if run busybox pgrep -x "x11vnc" > /dev/null 2>&1; then
        printf "${Tip} 检测到 X11VNC 已在运行，跳过启动。\n"
    else
        printf "${Info} 正在启动 X11VNC 服务...\n"
        run x11vnc -display ${DISPLAY_NUM} -forever -shared > /dev/null 2>&1 &
        sleep 2
        printf "${Info} X11VNC 已启动。\n"
    fi

    _local_ip=$(get_local_ip)
    printf "\n"
    printf "${Info} ${Green_font_prefix}图形显示环境已就绪！${Font_color_suffix}\n"
    printf "${Tip} 请使用 VNC 客户端连接至: ${Yellow_font_prefix}%s:5900${Font_color_suffix}\n" "$_local_ip"
    printf "${Tip} 所有带 RVIZ 的功能将在 VNC 窗口中显示。\n"
    printf "${Separator}\n"
    sleep 1
}

# =================================================
# 设备检查
# =================================================

check_dev() {
    printf "${Separator}\n"
    printf "${Info} 正在检查设备连接状态...\n"
    printf "${Separator}\n"

    # 检查底盘
    if [ -L "/dev/sparkBase" ] && [ -e "/dev/sparkBase" ]; then
        printf "${Info} ${Green_font_prefix}底盘已连接${Font_color_suffix}: /dev/sparkBase -> %s\n" \
            "$(run busybox readlink /dev/sparkBase)"
    elif [ -L "/dev/sparkBase" ]; then
        printf "${Error} 底盘软链接存在但设备已断开，请重新连接！(/dev/sparkBase)\n"
    else
        printf "${Error} 底盘未连接，请检查 /dev/sparkBase 软链接！(usbRules.sh 守护进程是否运行?)\n"
    fi

    # 检查激光雷达
    if [ -L "/dev/ydlidar" ] && [ -e "/dev/ydlidar" ]; then
        printf "${Info} ${Green_font_prefix}激光雷达已连接${Font_color_suffix}: /dev/ydlidar -> %s\n" \
            "$(run busybox readlink /dev/ydlidar)"
        LIDARTYPE="ydlidar_g6"
    elif [ -L "/dev/ydlidar" ]; then
        printf "${Error} 激光雷达软链接存在但设备已断开，请重新连接！(/dev/ydlidar)\n"
        LIDARTYPE="ydlidar_g6"
    else
        printf "${Error} 激光雷达未连接，请检查 /dev/ydlidar 软链接！\n"
        LIDARTYPE="ydlidar_g6"
    fi

    # 检查机械臂
    if [ -L "/dev/uarm" ] && [ -e "/dev/uarm" ]; then
        printf "${Info} ${Green_font_prefix}机械臂 (uArm) 已连接${Font_color_suffix}: /dev/uarm -> %s\n" \
            "$(run busybox readlink /dev/uarm)"
        ARMTYPE="uarm"
    elif [ -L "/dev/uarm" ]; then
        printf "${Warn} 机械臂软链接存在但设备已断开，请检查机械臂是否上电！(/dev/uarm)\n"
        ARMTYPE="uarm"
    else
        printf "${Warn} 未检测到机械臂 (/dev/uarm)，部分功能将不可用。\n"
        ARMTYPE="uarm"
    fi

    # 检查摄像头
    if ls /dev/video* > /dev/null 2>&1; then
        printf "${Info} ${Green_font_prefix}摄像头已检测到${Font_color_suffix} (类型: %s)\n" "$CAMERATYPE"
    else
        printf "${Warn} 未检测到摄像头设备 (/dev/video*)，请确认摄像头已连接！\n"
        printf "${Warn} ${Red_font_prefix}注意: 摄像头不可通过 USB 拓展坞连接开发板！${Font_color_suffix}\n"
    fi

    printf "${Separator}\n"
}

# =================================================
# 功能函数
# =================================================

# 1. 让机器人动起来
let_robot_go() {
    printf "${Info}\n"
    printf "${Info} 让机器人动起来\n"
    printf "${Info}\n"
    printf "${Info} 请确定：\n"
    printf "${Info}       A. 底盘已正确连接 (/dev/sparkBase)。\n"
    printf "${Info}       B. 激光雷达已正确连接 (/dev/ydlidar)。\n"
    printf "${Info}\n"
    printf "${Tip} 底盘控制说明：\n"
    printf "${Tip}   要控制底盘移动，需要在 ${Yellow_font_prefix}MobaXterm 中另开一个终端${Font_color_suffix} 并执行:\n"
    printf "${Tip}   ${Green_font_prefix}run roslaunch spark_teleop teleop_only.launch${Font_color_suffix}\n"
    printf "${Tip} 键盘方向对应：\n"
    printf "${Tip}                            \n"
    printf "${Tip}           w 前进           \n"
    printf "${Tip}   a 左转         d 右转   \n"
    printf "${Tip}           s 后退           \n"
    printf "${Tip}                            \n"
    printf "${Info} 退出请输入：Ctrl + c\n"
    printf "${Info}\n"
    press_enter "按回车键（Enter）开始（RVIZ 将在 VNC 窗口中显示）: "
    print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_teleop teleop.launch camera_type_tel:=${CAMERATYPE} lidar_type_tel:=${LIDARTYPE} arm_type_tel:=${ARMTYPE} enable_arm_tel:='yes'"
    DISPLAY=${DISPLAY_NUM} run roslaunch spark_teleop teleop.launch \
        camera_type_tel:=${CAMERATYPE} \
        lidar_type_tel:=${LIDARTYPE} \
        arm_type_tel:=${ARMTYPE} \
        enable_arm_tel:='yes'
}

# 2. 让SPARK跟着你走
depth_follow() {
    printf "${Info}\n"
    printf "${Info} 让SPARK跟着你走\n"
    printf "${Info}\n"
    printf "${Info} 请确定：\n"
    printf "${Info}       A. 深度摄像头 (%s) 已正确连接。\n" "$CAMERATYPE"
    printf "${Info}       B. ${Red_font_prefix}摄像头不可通过 USB 拓展坞连接开发板，否则无法正常使用！${Font_color_suffix}\n"
    printf "${Info}       C. 启动后，请站在机器人正前方约 1 米处，机器人将自动跟随您移动。\n"
    printf "${Info} 退出请输入：Ctrl + c\n"
    printf "${Info}\n"
    press_enter "按回车键（Enter）开始（RVIZ 将在 VNC 窗口中显示）: "
    print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_follower bringup.launch camera_type_tel:=${CAMERATYPE}"
    DISPLAY=${DISPLAY_NUM} run roslaunch spark_follower bringup.launch \
        camera_type_tel:=${CAMERATYPE}
}

# 3. 让SPARK使用激光雷达绘制地图
build_map_lidar() {
    printf "${Info}\n"
    printf "${Info} 让SPARK使用激光雷达绘制地图\n"
    printf "${Info}\n"
    printf "${Info} 请选择 SLAM 的方式：\n"
    printf "  ${Green_font_prefix}1.${Font_color_suffix} gmapping\n"
    printf "  ${Green_font_prefix}2.${Font_color_suffix} hector\n"
    printf "  ${Green_font_prefix}3.${Font_color_suffix} karto\n"
    printf "  ${Green_font_prefix}4.${Font_color_suffix} 退出请输入：Ctrl + c\n"
    printf "\n"
    printf "请输入数字 [1-3]: "
    read slamnum
    case "$slamnum" in
        1) SLAMTYPE="gmapping" ;;
        2) SLAMTYPE="hector" ;;
        3) SLAMTYPE="karto" ;;
        *) printf "${Error} 错误，默认使用 gmapping\n" ; SLAMTYPE="gmapping" ;;
    esac
    printf "${Info}\n"
    printf "${Info} 请确定：\n"
    printf "${Info}       A. 激光雷达已上电并正确连接 (/dev/ydlidar)。\n"
    printf "${Info}       B. 底盘已正确连接 (/dev/sparkBase)。\n"
    printf "${Info}\n"
    printf "${Tip} 底盘控制提示：\n"
    printf "${Tip}   建图过程中，需要在 ${Yellow_font_prefix}MobaXterm 中另开一个终端${Font_color_suffix} 执行以下命令控制底盘:\n"
    printf "${Tip}   ${Green_font_prefix}run roslaunch spark_teleop teleop_only.launch${Font_color_suffix}\n"
    printf "${Tip}   键盘 wsad 分别对应 前/后/左/右。\n"
    printf "${Info}\n"
    printf "${Tip} 保存地图：\n"
    printf "${Tip}   建图完成后，在 ${Yellow_font_prefix}新终端${Font_color_suffix} 中执行以下命令保存地图:\n"
    printf "${Tip}   ${Green_font_prefix}mkdir -p /data/local/release/usr/share/spark_slam/scripts${Font_color_suffix}\n"
    printf "${Tip}   ${Green_font_prefix}run roslaunch map_server map_server.launch${Font_color_suffix}\n"
    printf "${Info} 退出请输入：Ctrl + c\n"
    printf "${Info}\n"
    press_enter "按回车键（Enter）开始（RVIZ 将在 VNC 窗口中显示）: "
    print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_slam 2d_slam_teleop.launch slam_methods_tel:=${SLAMTYPE} camera_type_tel:=${CAMERATYPE} lidar_type_tel:=${LIDARTYPE}"
    DISPLAY=${DISPLAY_NUM} run roslaunch spark_slam 2d_slam_teleop.launch \
        slam_methods_tel:=${SLAMTYPE} \
        camera_type_tel:=${CAMERATYPE} \
        lidar_type_tel:=${LIDARTYPE}
}

# 4. 让SPARK使用深度摄像头绘制地图
build_map_camera() {
    printf "${Info}\n"
    printf "${Info} 让SPARK使用深度摄像头绘制地图\n"
    printf "${Info}\n"
    printf "${Info} 请选择建图的方式：\n"
    printf "  ${Green_font_prefix}1.${Font_color_suffix} RTAB-Map  (3D 建图，推荐)\n"
    printf "  ${Green_font_prefix}2.${Font_color_suffix} gmapping  (2D，摄像头模拟激光)\n"
    printf "  ${Green_font_prefix}3.${Font_color_suffix} hector    (2D，摄像头模拟激光)\n"
    printf "  ${Green_font_prefix}4.${Font_color_suffix} karto     (2D，摄像头模拟激光)\n"
    printf "  ${Green_font_prefix}5.${Font_color_suffix} 退出请输入：Ctrl + c\n"
    printf "\n"
    printf "请输入数字 [1-4]: "
    read camnum
    case "$camnum" in
        1) CAMMAP="rtabmap" ;;
        2) CAMMAP="gmapping" ;;
        3) CAMMAP="hector" ;;
        4) CAMMAP="karto" ;;
        *) printf "${Error} 错误，默认使用 RTAB-Map\n" ; CAMMAP="rtabmap" ;;
    esac
    printf "${Info}\n"
    printf "${Info} 请确定：\n"
    printf "${Info}       A. 深度摄像头 (%s) 已正确连接（不可通过 USB 拓展坞）。\n" "$CAMERATYPE"
    printf "${Info}       B. 底盘已正确连接 (/dev/sparkBase)。\n"
    printf "${Info}\n"
    printf "${Tip} 底盘控制提示：\n"
    printf "${Tip}   建图过程中，需要在 ${Yellow_font_prefix}MobaXterm 中另开一个终端${Font_color_suffix} 执行以下命令控制底盘:\n"
    printf "${Tip}   ${Green_font_prefix}run roslaunch spark_teleop teleop_only.launch${Font_color_suffix}\n"
    printf "${Tip}   键盘 wsad 分别对应 前/后/左/右。\n"
    printf "${Info}\n"
    if [ "$CAMMAP" = "rtabmap" ]; then
        printf "${Tip} 地图保存：\n"
        printf "${Tip}   建图完成后，地图数据库将自动保存至: /data/local/release/rtabmap.db\n"
    else
        printf "${Tip} 保存地图：\n"
        printf "${Tip}   建图完成后，在 ${Yellow_font_prefix}新终端${Font_color_suffix} 中执行以下命令保存地图:\n"
        printf "${Tip}   ${Green_font_prefix}mkdir -p /data/local/release/usr/share/spark_slam/scripts${Font_color_suffix}\n"
        printf "${Tip}   ${Green_font_prefix}run roslaunch map_server map_server.launch${Font_color_suffix}\n"
    fi
    printf "${Info} 退出请输入：Ctrl + c\n"
    printf "${Info}\n"
    press_enter "按回车键（Enter）开始（RVIZ 将在 VNC 窗口中显示）: "
    if [ "$CAMMAP" = "rtabmap" ]; then
        print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_rtabmap spark_rtabmap_teleop.launch camera_type_tel:=${CAMERATYPE}"
        DISPLAY=${DISPLAY_NUM} run roslaunch spark_rtabmap spark_rtabmap_teleop.launch \
            camera_type_tel:=${CAMERATYPE}
    else
        print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_slam depth_slam_teleop.launch slam_methods_tel:=${CAMMAP} camera_type_tel:=${CAMERATYPE}"
        DISPLAY=${DISPLAY_NUM} run roslaunch spark_slam depth_slam_teleop.launch \
            slam_methods_tel:=${CAMMAP} \
            camera_type_tel:=${CAMERATYPE}
    fi
}

# 5. 让SPARK使用激光雷达进行导航
navigation_lidar() {
    printf "${Info}\n"
    printf "${Info} 让SPARK使用激光雷达进行导航 (AMCL)\n"
    printf "${Info}\n"
    printf "${Info} 请确定：\n"
    printf "${Info}       A. 激光雷达已上电并正确连接 (/dev/ydlidar)。\n"
    printf "${Info}       B. 已有建图阶段保存的地图文件 (test_map.yaml / test_map.pgm)。\n"
    printf "${Info}\n"
    printf "${Tip} 导航操作说明：\n"
    printf "${Tip}   1. 导航启动后，在 VNC 的 RVIZ 中点击 '2D Pose Estimate' 并在地图上手动初始化机器人位置。\n"
    printf "${Tip}   2. 初始化成功后，点击 '2D Nav Goal' 并在地图上指定导航目标点，机器人将自主导航。\n"
    printf "${Info} 退出请输入：Ctrl + c\n"
    printf "${Info}\n"
    press_enter "按回车键（Enter）开始（RVIZ 将在 VNC 窗口中显示）: "
    print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_navigation amcl_demo_lidar_rviz.launch camera_type_tel:=${CAMERATYPE} lidar_type_tel:=${LIDARTYPE}"
    DISPLAY=${DISPLAY_NUM} run roslaunch spark_navigation amcl_demo_lidar_rviz.launch \
        camera_type_tel:=${CAMERATYPE} \
        lidar_type_tel:=${LIDARTYPE}
}

# 6. 让SPARK使用深度摄像头进行导航
navigation_camera() {
    printf "${Info}\n"
    printf "${Info} 让SPARK使用深度摄像头进行导航\n"
    printf "${Info}\n"
    printf "${Info} 请选择导航的方式：\n"
    printf "  ${Green_font_prefix}1.${Font_color_suffix} RTAB-Map 导航  (需 rtabmap.db 地图)\n"
    printf "  ${Green_font_prefix}2.${Font_color_suffix} 2D AMCL 导航   (需深度摄像头 2D 建图地图)\n"
    printf "  ${Green_font_prefix}3.${Font_color_suffix} 退出请输入：Ctrl + c\n"
    printf "\n"
    printf "请输入数字 [1-2]: "
    read navnum
    case "$navnum" in
        1) CAMNAVTYPE="rtabmap" ;;
        2) CAMNAVTYPE="amcl2d" ;;
        *) printf "${Error} 错误，默认使用 RTAB-Map 导航\n" ; CAMNAVTYPE="rtabmap" ;;
    esac
    printf "${Info}\n"
    printf "${Info} 请确定：\n"
    printf "${Info}       A. 深度摄像头 (%s) 已正确连接（不可通过 USB 拓展坞）。\n" "$CAMERATYPE"
    if [ "$CAMNAVTYPE" = "rtabmap" ]; then
        printf "${Info}       B. 已有建图阶段保存的地图数据库 (/data/local/release/rtabmap.db)。\n"
        printf "${Info}       C. 请将机器人放置在建图时的起始点位置。\n"
        printf "${Info}\n"
        printf "${Tip} 导航操作说明：\n"
        printf "${Tip}   导航启动后，在 VNC 的 RVIZ 中点击 '2D Nav Goal' 并在地图上指定导航目标点。\n"
        printf "${Tip}   如需加载 3D 地图，点击 RVIZ 中 Display -> Rtabmap cloud -> Download map。\n"
    else
        printf "${Info}       B. 已有深度摄像头 2D 建图阶段保存的地图文件 (test_map.yaml / test_map.pgm)。\n"
        printf "${Info}\n"
        printf "${Tip} 导航操作说明：\n"
        printf "${Tip}   1. 导航启动后，在 VNC 的 RVIZ 中点击 '2D Pose Estimate' 并在地图上手动初始化机器人位置。\n"
        printf "${Tip}   2. 初始化成功后，点击 '2D Nav Goal' 并在地图上指定导航目标点，机器人将自主导航。\n"
    fi
    printf "${Info} 退出请输入：Ctrl + c\n"
    printf "${Info}\n"
    press_enter "按回车键（Enter）开始（RVIZ 将在 VNC 窗口中显示）: "
    if [ "$CAMNAVTYPE" = "rtabmap" ]; then
        print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_rtabmap spark_rtabmap_nav.launch camera_type_tel:=${CAMERATYPE}"
        DISPLAY=${DISPLAY_NUM} run roslaunch spark_rtabmap spark_rtabmap_nav.launch \
            camera_type_tel:=${CAMERATYPE}
    else
        print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_navigation amcl_demo_rviz.launch camera_type_tel:=${CAMERATYPE}"
        DISPLAY=${DISPLAY_NUM} run roslaunch spark_navigation amcl_demo_rviz.launch \
            camera_type_tel:=${CAMERATYPE}
    fi
}

# 7. 机械臂与摄像头标定
hand_eye_calibration() {
    printf "${Info}\n"
    printf "${Info} 机械臂与摄像头标定\n"
    printf "${Info}\n"
    printf "${Info} 请确定：\n"
    printf "${Info}       A. 摄像头已反向向下安装好。\n"
    printf "${Info}       B. 机械臂已正常上电。\n"
    printf "${Info}       C. 标定程序启动后，请在 VNC 窗口中查看相机视角并调整角度。\n"
    printf "${Info} 退出请输入：Ctrl + c\n"
    printf "${Info}\n"
    press_enter "按回车键（Enter）开始（RVIZ 将在 VNC 窗口中显示）: "
    print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_carry_object spark_carry_cal_cv3.launch camera_type_tel:=${CAMERATYPE} lidar_type_tel:=${LIDARTYPE}"
    DISPLAY=${DISPLAY_NUM} run roslaunch spark_carry_object spark_carry_cal_cv3.launch \
        camera_type_tel:=${CAMERATYPE} \
        lidar_type_tel:=${LIDARTYPE}
    printf "\n"
    printf "${Info} 程序启动后，请在 ${Yellow_font_prefix}新终端${Font_color_suffix} 中执行以下命令以触发标定:\n"
    printf "${Info} ${Green_font_prefix}run rostopic pub /start_topic std_msgs/String \"data: 'start'\"${Font_color_suffix}\n"
}

# 8. 让SPARK通过机械臂进行视觉抓取
object_grasping() {
    printf "${Info}\n"
    printf "${Info} 让SPARK通过机械臂进行视觉抓取\n"
    printf "${Info}\n"
    printf "${Info} 请确定：\n"
    printf "${Info}       A. 已完成机械臂与摄像头标定，标定文件已保存至正确路径。\n"
    printf "${Info}       B. 机械臂已正常上电。\n"
    printf "${Info}       C. 已准备好目标物品。\n"
    printf "${Info} 退出请输入：Ctrl + c\n"
    printf "${Info}\n"
    printf "${Info} 程序启动后，请在 ${Yellow_font_prefix}新终端${Font_color_suffix} 中执行以下命令以开始抓取:\n"
    printf "${Info} ${Green_font_prefix}run rosservice call /s_carry_object 'type: 1'${Font_color_suffix}\n"
    printf "${Info}\n"
    press_enter "按回车键（Enter）开始（RVIZ 将在 VNC 窗口中显示）: "
    print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_carry_object spark_carry_object_only_cv3.launch camera_type_tel:=${CAMERATYPE} lidar_type_tel:=${LIDARTYPE}"
    DISPLAY=${DISPLAY_NUM} run roslaunch spark_carry_object spark_carry_object_only_cv3.launch \
        camera_type_tel:=${CAMERATYPE} \
        lidar_type_tel:=${LIDARTYPE}
}

# 9. 深度学习目标检测
deep_learning() {
    printf "${Info}\n"
    printf "${Info} 让SPARK使用深度学习识别目标\n"
    printf "${Info}\n"
    printf "${Info} 请选择深度学习的方式：\n"
    printf "${Info}   ${Green_font_prefix}1.${Font_color_suffix} YOLOv3\n"
    printf "${Info}   ${Blue_font_prefix}     更多深度学习方式敬请期待...${Font_color_suffix}\n"
    printf "${Info}   ${Green_font_prefix}4.${Font_color_suffix} 退出请输入：Ctrl + c\n"
    printf "\n"
    printf "请输入数字 [1]: "
    read _dl_choice
    case "$_dl_choice" in
        1)
            printf "${Info}\n"
            printf "${Info} 让SPARK使用深度学习识别目标 (YOLOv3)\n"
            printf "${Info}\n"
            printf "${Info} 请确定：\n"
            printf "${Info}       A. 深度摄像头 (%s) 已正确连接。\n" "$CAMERATYPE"
            printf "${Info}       B. ${Red_font_prefix}摄像头不可通过 USB 拓展坞连接开发板，否则无法正常使用！${Font_color_suffix}\n"
            printf "${Info}       C. YOLOv3 模型权重文件已就绪。\n"
            printf "${Info} 退出请输入：Ctrl + c\n"
            printf "${Info}\n"
            press_enter "按回车键（Enter）开始（RVIZ 将在 VNC 窗口中显示）: "
            print_command "DISPLAY=${DISPLAY_NUM} run roslaunch darknet_ros deeplearn_darknet_yoloV3.launch camera_type_tel:=${CAMERATYPE}"
            DISPLAY=${DISPLAY_NUM} run roslaunch darknet_ros deeplearn_darknet_yoloV3.launch \
                camera_type_tel:=${CAMERATYPE}
            ;;
        *)
            printf "${Error} 请输入正确的数字 [1]\n"
            ;;
    esac
}

# =================================================
# 主菜单
# =================================================

show_menu() {
    clear
    printf "\n"
    printf "${Separator}\n"
    printf "  M-Robots (OpenHarmony) 一键启动脚本 ${Red_font_prefix}[v%s]${Font_color_suffix}\n" "$sh_ver"
    printf "\n"
    printf "  请根据功能说明选择相应的序号。\n"
    printf "\n"
    printf "  ${Green_font_prefix}  1.${Font_color_suffix} 让机器人动起来\n"
    printf "  ${Green_font_prefix}  2.${Font_color_suffix} 让SPARK跟着你走\n"
    printf "  ${Green_font_prefix}  3.${Font_color_suffix} 让SPARK使用激光雷达绘制地图\n"
    printf "  ${Green_font_prefix}  4.${Font_color_suffix} 让SPARK使用深度摄像头绘制地图\n"
    printf "  ${Green_font_prefix}  5.${Font_color_suffix} 让SPARK使用激光雷达进行导航\n"
    printf "  ${Green_font_prefix}  6.${Font_color_suffix} 让SPARK使用深度摄像头进行导航\n"
    printf "  ${Green_font_prefix}  7.${Font_color_suffix} 机械臂与摄像头标定\n"
    printf "  ${Green_font_prefix}  8.${Font_color_suffix} 让SPARK通过机械臂进行视觉抓取\n"
    printf "  ${Green_font_prefix}  9.${Font_color_suffix} 让SPARK使用深度学习识别目标\n"
    printf "\n"
    printf "${Separator}\n"
    printf "  ${Green_font_prefix}  0.${Font_color_suffix} 退出脚本（将同时关闭 Xvfb 和 X11VNC）\n"
    printf "${Separator}\n"
    check_dev
}

# =================================================
# 脚本入口
# =================================================

# 第一步：检查并挂载文件系统
check_mount

# 第二步：启动虚拟屏幕和 VNC 服务
start_virtual_screen

# 第三步：进入主循环
while true; do
    show_menu
    printf "请输入数字 [0-9]: "
    read num
    case "$num" in
        1) let_robot_go ;;
        2) depth_follow ;;
        3) build_map_lidar ;;
        4) build_map_camera ;;
        5) navigation_lidar ;;
        6) navigation_camera ;;
        7) hand_eye_calibration ;;
        8) object_grasping ;;
        9) deep_learning ;;
        0) cleanup ;;
        *)
            printf "${Error} 请输入正确的数字 [0-9]\n"
            ;;
    esac
    printf "\n"
    printf "${Info} 功能已结束，按回车键返回主菜单...\n"
    read _dummy
done
