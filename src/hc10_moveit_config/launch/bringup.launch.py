import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    moveit_share = get_package_share_directory('hc10_moveit_config')
    mfja_share = get_package_share_directory('mfja_3rd_floor_bringup')
    simulation = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            os.path.join(mfja_share, 'launch', 'single_industrial_robot.launch.py')),
        launch_arguments={
            'robot': 'hc10',
            'gui': LaunchConfiguration('gui'),
            'use_sim_time': 'true',
        }.items())
    adapter = Node(
        package='hc10_mfja_control_adapter', executable='hc10_control_adapter',
        output='screen', parameters=[{'use_sim_time': True}])
    moveit = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            os.path.join(moveit_share, 'launch', 'moveit.launch.py')),
        launch_arguments={
            'use_sim_time': 'true',
            'use_rviz': LaunchConfiguration('use_rviz'),
        }.items())
    return LaunchDescription([
        DeclareLaunchArgument('gui', default_value='true'),
        DeclareLaunchArgument('use_rviz', default_value='true'),
        simulation, adapter, moveit,
    ])
