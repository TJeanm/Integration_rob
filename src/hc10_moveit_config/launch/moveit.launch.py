from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.conditions import IfCondition
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node
from moveit_configs_utils import MoveItConfigsBuilder


def generate_launch_description():
    config = (
        MoveItConfigsBuilder('hc10', package_name='hc10_moveit_config')
        .robot_description(file_path='urdf/hc10_mfja.urdf.xacro')
        .robot_description_semantic(file_path='config/hc10_mfja.srdf')
        .robot_description_kinematics(file_path='config/kinematics.yaml')
        .joint_limits(file_path='config/joint_limits.yaml')
        .planning_pipelines(default_planning_pipeline='ompl', pipelines=['ompl'])
        .trajectory_execution(file_path='config/moveit_controllers.yaml', moveit_manage_controllers=False)
        .planning_scene_monitor(publish_robot_description=True, publish_robot_description_semantic=True)
        .to_moveit_configs()
    )
    params = config.to_dict()
    params.update({
        'octomap_frame': 'base_link',
        'octomap_resolution': 0.04,
        'sensors': ['hc10_rgbd'],
        'hc10_rgbd': {
            'sensor_plugin': 'occupancy_map_monitor/PointCloudOctomapUpdater',
            'point_cloud_topic': '/hc10/collision_cloud',
            'max_range': 5.0,
            'point_subsample': 2,
            # Gazebo and MoveIt meshes differ by a few centimetres around the
            # simulated jaws. A wider self-filter removes those robot returns
            # before OctoMap insertion, preventing false start collisions on
            # repeated cycles while preserving the surrounding geometry.
            'padding_offset': 0.05,
            'padding_scale': 1.0,
            'max_update_rate': 1.0,
            'filtered_cloud_topic': '/room_315/perception/collision_points',
        },
    })
    common = {'use_sim_time': LaunchConfiguration('use_sim_time')}
    joint_state_remap = [('/joint_states', '/yaskawa_hc10_1/joint_states')]
    return LaunchDescription([
        DeclareLaunchArgument('use_sim_time', default_value='true'),
        DeclareLaunchArgument('use_rviz', default_value='true'),
        Node(
            package='tf2_ros', executable='static_transform_publisher',
            arguments=[
                '--x', '-1.70', '--y', '-0.2622', '--z', '3.33',
                '--qx', '0.5', '--qy', '0.5', '--qz', '-0.5', '--qw', '0.5',
                '--frame-id', 'base_link',
                '--child-frame-id', 'room315_right_rail_rgbd_optical_frame',
            ]),
        Node(
            package='robot_state_publisher', executable='robot_state_publisher',
            name='hc10_moveit_robot_state_publisher', output='screen',
            parameters=[config.robot_description, common], remappings=joint_state_remap),
        Node(
            package='moveit_ros_move_group', executable='move_group',
            output='screen', parameters=[params, common], remappings=joint_state_remap),
        Node(
            package='rviz2', executable='rviz2', name='hc10_moveit_rviz', output='screen',
            arguments=['-d', str(config.package_path / 'config/moveit.rviz')],
            parameters=[
                config.robot_description,
                config.robot_description_semantic,
                config.robot_description_kinematics,
                config.planning_pipelines,
                config.joint_limits,
                common,
            ],
            remappings=joint_state_remap,
            condition=IfCondition(LaunchConfiguration('use_rviz'))),
    ])
