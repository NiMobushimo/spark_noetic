#!/bin/sh
#=================================================
#   System Required: OpenHarmony (M-Robots)
#   Description: M-Robots 一键启动管理脚本
#   Based on: spark_noetic / onekey.sh
#   Site: https://github.com/NiMobushimo/spark_noetic
#=================================================

# --- 脚本版本 ---
sh_ver="1.0"

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
XVFB_PID=""
X11VNC_PID=""
DISPLAY_NUM=":0"

# =================================================
# 工具函数
# =================================================

# 打印执行命令（高亮显示）
print_command() {
    echo "${Yellow_font_prefix}>>> ${Green_font_prefix}$1${Font_color_suffix}"
}

# 清理并退出（Ctrl+C 或正常退出时调用）
cleanup() {
    echo ""
    echo "${Info} 正在停止所有 ROS 节点..."
    run killall -9 rosmaster rosout > /dev/null 2>&1
    echo "${Info} 正在关闭虚拟屏幕 (Xvfb) 和 X11VNC 服务..."
    if [ -n "$XVFB_PID" ]; then
        kill "$XVFB_PID" > /dev/null 2>&1
        echo "${Info} Xvfb (PID: $XVFB_PID) 已关闭。"
    fi
    if [ -n "$X11VNC_PID" ]; then
        kill "$X11VNC_PID" > /dev/null 2>&1
        echo "${Info} X11VNC (PID: $X11VNC_PID) 已关闭。"
    fi
    echo "${Info} 清理完成，脚本已退出。"
    stty sane
    exit 0
}

# 捕获 Ctrl+C (INT) 和终止信号 (TERM)
trap cleanup INT TERM

# =================================================
# 环境初始化
# =================================================

# 检查并挂载文件系统（开发板首次启动需要）
check_mount() {
    # 检查 /data/local/release 是否可写
    if ! touch /data/local/release/.write_test > /dev/null 2>&1; then
        echo "${Info} 检测到文件系统为只读，正在重新挂载..."
        mount -o remount,rw /
    else
        rm -f /data/local/release/.write_test
    fi
}

# 启动虚拟屏幕和 VNC 服务
start_virtual_screen() {
    echo "${Separator}"
    echo "${Info} 正在初始化图形显示环境..."
    echo "${Separator}"

    # 检查 Xvfb 是否已在运行
    if run pgrep -x "Xvfb" > /dev/null 2>&1; then
        echo "${Tip} 检测到 Xvfb 已在运行，跳过启动。"
    else
        echo "${Info} 正在启动 X Virtual Framebuffer (Xvfb)..."
        run startxvfb -screen 0 1400x1000x24 &
        XVFB_PID=$!
        sleep 2
        echo "${Info} Xvfb 已启动 (PID: $XVFB_PID)。"
    fi

    # 检查 x11vnc 是否已在运行
    if run pgrep -x "x11vnc" > /dev/null 2>&1; then
        echo "${Tip} 检测到 X11VNC 已在运行，跳过启动。"
    else
        echo "${Info} 正在启动 X11VNC 服务..."
        run x11vnc -display ${DISPLAY_NUM} -forever -shared > /dev/null 2>&1 &
        X11VNC_PID=$!
        sleep 2
        echo "${Info} X11VNC 已启动 (PID: $X11VNC_PID)。"
    fi

    # 获取本机 IP 地址用于提示
    _local_ip=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
    echo ""
    echo "${Info} ${Green_font_prefix}图形显示环境已就绪！${Font_color_suffix}"
    echo "${Tip} 请使用 VNC 客户端连接至: ${Yellow_font_prefix}${_local_ip}:5900${Font_color_suffix}"
    echo "${Tip} 所有带 RVIZ 的功能将在 VNC 窗口中显示。"
    echo "${Separator}"
    sleep 1
}

# =================================================
# 设备检查
# =================================================

# 检查设备连接（通过软链接判断，适配 OpenHarmony）
check_dev() {
    echo "${Separator}"
    echo "${Info} 正在检查设备连接状态..."
    echo "${Separator}"

    # 检查底盘
    if [ -L "/dev/sparkBase" ] && [ -e "/dev/sparkBase" ]; then
        echo "${Info} ${Green_font_prefix}底盘已连接${Font_color_suffix}: /dev/sparkBase -> $(readlink /dev/sparkBase)"
    elif [ -L "/dev/sparkBase" ]; then
        echo "${Error} 底盘软链接存在但设备已断开，请重新连接！(/dev/sparkBase)"
    else
        echo "${Error} 底盘未连接，请检查 /dev/sparkBase 软链接！(usbRules.sh 守护进程是否运行?)"
    fi

    # 检查激光雷达
    if [ -L "/dev/ydlidar" ] && [ -e "/dev/ydlidar" ]; then
        echo "${Info} ${Green_font_prefix}激光雷达已连接${Font_color_suffix}: /dev/ydlidar -> $(readlink /dev/ydlidar)"
        LIDARTYPE="ydlidar_g6"
    elif [ -L "/dev/ydlidar" ]; then
        echo "${Error} 激光雷达软链接存在但设备已断开，请重新连接！(/dev/ydlidar)"
        LIDARTYPE="ydlidar_g6"
    else
        echo "${Error} 激光雷达未连接，请检查 /dev/ydlidar 软链接！"
        LIDARTYPE="ydlidar_g6"
    fi

    # 检查机械臂
    if [ -L "/dev/uarm" ] && [ -e "/dev/uarm" ]; then
        echo "${Info} ${Green_font_prefix}机械臂 (uArm) 已连接${Font_color_suffix}: /dev/uarm -> $(readlink /dev/uarm)"
        ARMTYPE="uarm"
    elif [ -L "/dev/uarm" ]; then
        echo "${Warn} 机械臂软链接存在但设备已断开，请检查机械臂是否上电！(/dev/uarm)"
        ARMTYPE="uarm"
    else
        echo "${Warn} 未检测到机械臂 (/dev/uarm)，部分功能将不可用。"
        ARMTYPE="uarm"
    fi

    # 摄像头（深度摄像头通过 USB 直连，不使用串口软链接）
    # 检查 /dev/video* 设备节点是否存在
    if ls /dev/video* > /dev/null 2>&1; then
        echo "${Info} ${Green_font_prefix}摄像头已检测到${Font_color_suffix} (类型: ${CAMERATYPE})"
    else
        echo "${Warn} 未检测到摄像头设备 (/dev/video*)，请确认摄像头已连接！"
        echo "${Warn} ${Red_font_prefix}注意: 摄像头不可通过 USB 拓展坞连接开发板！${Font_color_suffix}"
    fi

    echo "${Separator}"
}

# =================================================
# 功能函数
# =================================================

# 1. 让机器人动起来（键盘控制）
let_robot_go() {
    echo "${Info}"
    echo "${Info} 让机器人动起来 (键盘控制 + RVIZ 可视化)"
    echo "${Separator}"
    echo "${Tip} 底盘控制说明："
    echo "${Tip}   要控制底盘移动，需要在 ${Yellow_font_prefix}MobaXterm 中另开一个终端${Font_color_suffix} 并执行:"
    echo "${Tip}   ${Green_font_prefix}run roslaunch spark_teleop teleop_only.launch${Font_color_suffix}"
    echo "${Tip} 键盘方向对应："
    echo "${Tip}           w 前进           "
    echo "${Tip}   a 左转         d 右转   "
    echo "${Tip}           s 后退           "
    echo "${Separator}"
    echo && read -p "按回车键（Enter）开始启动主程序（RVIZ 将在 VNC 窗口中显示）: "
    print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_teleop teleop.launch camera_type_tel:=${CAMERATYPE} lidar_type_tel:=${LIDARTYPE} arm_type_tel:=${ARMTYPE} enable_arm_tel:='yes'"
    DISPLAY=${DISPLAY_NUM} run roslaunch spark_teleop teleop.launch camera_type_tel:=${CAMERATYPE} lidar_type_tel:=${LIDARTYPE} arm_type_tel:=${ARMTYPE} enable_arm_tel:='yes'
}

# 2. 手眼标定
hand_eye_calibration() {
    echo "${Info}"
    echo "${Info} 手眼标定"
    echo "${Separator}"
    echo "${Tip} 请确认以下事项后再继续："
    echo "${Tip}   A. 摄像头已反向向下安装好。"
    echo "${Tip}   B. 机械臂已正常上电。"
    echo "${Tip}   C. 标定程序启动后，请在 VNC 窗口中查看相机视角并调整角度。"
    echo "${Separator}"
    echo && read -p "按回车键（Enter）开始（RVIZ 将在 VNC 窗口中显示）: "
    print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_carry_object spark_carry_cal_cv3.launch camera_type_tel:=${CAMERATYPE} lidar_type_tel:=${LIDARTYPE}"
    DISPLAY=${DISPLAY_NUM} run roslaunch spark_carry_object spark_carry_cal_cv3.launch camera_type_tel:=${CAMERATYPE} lidar_type_tel:=${LIDARTYPE}
    echo ""
    echo "${Info} 程序启动后，请在 ${Yellow_font_prefix}新终端${Font_color_suffix} 中执行以下命令以触发标定:"
    echo "${Info} ${Green_font_prefix}run rostopic pub /start_topic std_msgs/String \"data: 'start'\"${Font_color_suffix}"
}

# 3. 物品抓取
object_grasping() {
    echo "${Info}"
    echo "${Info} 物品抓取"
    echo "${Separator}"
    echo "${Tip} 请确认以下事项后再继续："
    echo "${Tip}   A. 已完成手眼标定，标定文件已保存至正确路径。"
    echo "${Tip}   B. 机械臂已正常上电。"
    echo "${Tip}   C. 已准备好目标物品。"
    echo "${Separator}"
    echo && read -p "按回车键（Enter）开始（RVIZ 将在 VNC 窗口中显示）: "
    print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_carry_object spark_carry_object_only_cv3.launch camera_type_tel:=${CAMERATYPE} lidar_type_tel:=${LIDARTYPE}"
    DISPLAY=${DISPLAY_NUM} run roslaunch spark_carry_object spark_carry_object_only_cv3.launch camera_type_tel:=${CAMERATYPE} lidar_type_tel:=${LIDARTYPE}
    echo ""
    echo "${Info} 程序启动后，请在 ${Yellow_font_prefix}新终端${Font_color_suffix} 中执行以下命令以开始抓取:"
    echo "${Info} ${Green_font_prefix}run rosservice call /s_carry_object 'type: 1'${Font_color_suffix}"
}

# 4. 激光雷达建图（gmapping）
build_map_lidar() {
    echo "${Info}"
    echo "${Info} 激光雷达建图 (GMapping)"
    echo "${Separator}"
    echo "${Tip} 请确认以下事项后再继续："
    echo "${Tip}   A. 激光雷达已上电并正确连接 (/dev/ydlidar)。"
    echo "${Tip}   B. 底盘已正确连接 (/dev/sparkBase)。"
    echo "${Tip} ${Yellow_font_prefix}底盘控制提示:${Font_color_suffix}"
    echo "${Tip}   建图过程中，需要在 ${Yellow_font_prefix}MobaXterm 中另开一个终端${Font_color_suffix} 执行以下命令控制底盘:"
    echo "${Tip}   ${Green_font_prefix}run roslaunch spark_teleop teleop_only.launch${Font_color_suffix}"
    echo "${Tip}   键盘 wsad 分别对应 前/后/左/右。"
    echo "${Tip} ${Yellow_font_prefix}保存地图:${Font_color_suffix}"
    echo "${Tip}   建图完成后，在 ${Yellow_font_prefix}新终端${Font_color_suffix} 中执行以下命令保存地图:"
    echo "${Tip}   ${Green_font_prefix}mkdir -p /data/local/release/usr/share/spark_slam/scripts${Font_color_suffix}"
    echo "${Tip}   ${Green_font_prefix}run roslaunch map_server map_server.launch${Font_color_suffix}"
    echo "${Tip}   更多建图方式敬请期待..."
    echo "${Separator}"
    echo && read -p "按回车键（Enter）开始（RVIZ 将在 VNC 窗口中显示）: "
    print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_slam 2d_slam_teleop.launch slam_methods_tel:=gmapping camera_type_tel:=${CAMERATYPE} lidar_type_tel:=${LIDARTYPE}"
    DISPLAY=${DISPLAY_NUM} run roslaunch spark_slam 2d_slam_teleop.launch slam_methods_tel:="gmapping" camera_type_tel:=${CAMERATYPE} lidar_type_tel:=${LIDARTYPE}
}

# 5. 深度摄像头建图（RTAB-Map）
build_map_camera() {
    echo "${Info}"
    echo "${Info} 深度摄像头建图 (RTAB-Map)"
    echo "${Separator}"
    echo "${Tip} 请确认以下事项后再继续："
    echo "${Tip}   A. 深度摄像头 (${CAMERATYPE}) 已正确连接（不可通过 USB 拓展坞）。"
    echo "${Tip}   B. 底盘已正确连接 (/dev/sparkBase)。"
    echo "${Tip} ${Yellow_font_prefix}底盘控制提示:${Font_color_suffix}"
    echo "${Tip}   建图过程中，需要在 ${Yellow_font_prefix}MobaXterm 中另开一个终端${Font_color_suffix} 执行以下命令控制底盘:"
    echo "${Tip}   ${Green_font_prefix}run roslaunch spark_teleop teleop_only.launch${Font_color_suffix}"
    echo "${Tip}   键盘 wsad 分别对应 前/后/左/右。"
    echo "${Tip} ${Yellow_font_prefix}地图保存:${Font_color_suffix}"
    echo "${Tip}   建图完成后，地图数据库将自动保存至: /data/local/release/rtabmap.db"
    echo "${Tip}   更多建图方式敬请期待..."
    echo "${Separator}"
    echo && read -p "按回车键（Enter）开始（RVIZ 将在 VNC 窗口中显示）: "
    print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_rtabmap spark_rtabmap_teleop.launch camera_type_tel:=${CAMERATYPE}"
    DISPLAY=${DISPLAY_NUM} run roslaunch spark_rtabmap spark_rtabmap_teleop.launch camera_type_tel:=${CAMERATYPE}
}

# 6. 激光雷达导航
navigation_lidar() {
    echo "${Info}"
    echo "${Info} 激光雷达导航 (AMCL)"
    echo "${Separator}"
    echo "${Tip} 请确认以下事项后再继续："
    echo "${Tip}   A. 激光雷达已上电并正确连接 (/dev/ydlidar)。"
    echo "${Tip}   B. 已有建图阶段保存的地图文件 (test_map.yaml / test_map.pgm)。"
    echo "${Tip} ${Yellow_font_prefix}导航操作说明:${Font_color_suffix}"
    echo "${Tip}   1. 导航启动后，在 VNC 的 RVIZ 中点击 '2D Pose Estimate' 并在地图上手动初始化机器人位置。"
    echo "${Tip}   2. 初始化成功后，点击 '2D Nav Goal' 并在地图上指定导航目标点，机器人将自主导航。"
    echo "${Separator}"
    echo && read -p "按回车键（Enter）开始（RVIZ 将在 VNC 窗口中显示）: "
    print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_navigation amcl_demo_lidar_rviz.launch camera_type_tel:=${CAMERATYPE} lidar_type_tel:=${LIDARTYPE}"
    DISPLAY=${DISPLAY_NUM} run roslaunch spark_navigation amcl_demo_lidar_rviz.launch camera_type_tel:=${CAMERATYPE} lidar_type_tel:=${LIDARTYPE}
}

# 7. 深度摄像头导航
navigation_camera() {
    echo "${Info}"
    echo "${Info} 深度摄像头导航 (RTAB-Map)"
    echo "${Separator}"
    echo "${Tip} 请确认以下事项后再继续："
    echo "${Tip}   A. 深度摄像头 (${CAMERATYPE}) 已正确连接（不可通过 USB 拓展坞）。"
    echo "${Tip}   B. 已有建图阶段保存的地图数据库 (/data/local/release/rtabmap.db)。"
    echo "${Tip}   C. 请将机器人放置在建图时的起始点位置。"
    echo "${Tip} ${Yellow_font_prefix}导航操作说明:${Font_color_suffix}"
    echo "${Tip}   导航启动后，在 VNC 的 RVIZ 中点击 '2D Nav Goal' 并在地图上指定导航目标点。"
    echo "${Tip}   如需加载 3D 地图，点击 RVIZ 中 Display -> Rtabmap cloud -> Download map。"
    echo "${Separator}"
    echo && read -p "按回车键（Enter）开始（RVIZ 将在 VNC 窗口中显示）: "
    print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_rtabmap spark_rtabmap_nav.launch camera_type_tel:=${CAMERATYPE}"
    DISPLAY=${DISPLAY_NUM} run roslaunch spark_rtabmap spark_rtabmap_nav.launch camera_type_tel:=${CAMERATYPE}
}

# 8. 深度跟随
depth_follow() {
    echo "${Info}"
    echo "${Info} 深度跟随"
    echo "${Separator}"
    echo "${Tip} 请确认以下事项后再继续："
    echo "${Tip}   A. 深度摄像头 (${CAMERATYPE}) 已正确连接。"
    echo "${Tip}   B. ${Red_font_prefix}摄像头不可通过 USB 拓展坞连接开发板，否则无法正常使用！${Font_color_suffix}"
    echo "${Tip}   C. 启动后，请站在机器人正前方约 1 米处，机器人将自动跟随您移动。"
    echo "${Separator}"
    echo && read -p "按回车键（Enter）开始（RVIZ 将在 VNC 窗口中显示）: "
    print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_follower bringup.launch camera_type_tel:=${CAMERATYPE}"
    DISPLAY=${DISPLAY_NUM} run roslaunch spark_follower bringup.launch camera_type_tel:=${CAMERATYPE}
}

# =================================================
# 主菜单
# =================================================

show_menu() {
    clear
    echo ""
    echo "${Separator}"
    echo "  M-Robots (OpenHarmony) 一键启动脚本 ${Red_font_prefix}[v${sh_ver}]${Font_color_suffix}"
    echo "  基于 spark_noetic 移植 | 请根据功能说明选择序号"
    echo "${Separator}"
    echo ""
    echo "  ${Green_font_prefix}基础功能${Font_color_suffix}"
    echo "  ${Green_font_prefix}  1.${Font_color_suffix} 让机器人动起来 (键盘控制 + RVIZ)"
    echo "  ${Green_font_prefix}  2.${Font_color_suffix} 手眼标定"
    echo "  ${Green_font_prefix}  3.${Font_color_suffix} 物品抓取"
    echo ""
    echo "  ${Green_font_prefix}建图功能${Font_color_suffix}"
    echo "  ${Green_font_prefix}  4.${Font_color_suffix} 激光雷达建图 (GMapping)"
    echo "  ${Green_font_prefix}  5.${Font_color_suffix} 深度摄像头建图 (RTAB-Map)"
    echo "         ${Blue_font_prefix}更多建图方式敬请期待...${Font_color_suffix}"
    echo ""
    echo "  ${Green_font_prefix}导航功能${Font_color_suffix}"
    echo "  ${Green_font_prefix}  6.${Font_color_suffix} 激光雷达导航 (AMCL)"
    echo "  ${Green_font_prefix}  7.${Font_color_suffix} 深度摄像头导航 (RTAB-Map)"
    echo ""
    echo "  ${Green_font_prefix}应用功能${Font_color_suffix}"
    echo "  ${Green_font_prefix}  8.${Font_color_suffix} 深度跟随"
    echo ""
    echo "${Separator}"
    echo "  ${Green_font_prefix}  0.${Font_color_suffix} 退出脚本（将同时关闭 Xvfb 和 X11VNC）"
    echo "${Separator}"
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
    echo && read -p "请输入数字 [0-8]: " num
    case "$num" in
        1)
            let_robot_go
            ;;
        2)
            hand_eye_calibration
            ;;
        3)
            object_grasping
            ;;
        4)
            build_map_lidar
            ;;
        5)
            build_map_camera
            ;;
        6)
            navigation_lidar
            ;;
        7)
            navigation_camera
            ;;
        8)
            depth_follow
            ;;
        0)
            cleanup
            ;;
        *)
            echo "${Error} 请输入正确的数字 [0-8]"
            ;;
    esac
    echo ""
    echo "${Info} 功能已结束，按回车键返回主菜单..."
    read dummy
done
