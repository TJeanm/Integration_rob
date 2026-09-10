"""Send a tool0 pose in base_link to MoveIt for planning and execution."""
import argparse
import math
import time

import rclpy
from rclpy.action import ActionClient
from rclpy.callback_groups import ReentrantCallbackGroup
from rclpy.node import Node
from rclpy.parameter import Parameter
from moveit_msgs.action import MoveGroup
from moveit_msgs.msg import MoveItErrorCodes
from pymoveit2 import MoveIt2, MoveIt2State

from hc10_moveit_api.joint_goal import JOINT_NAMES


def finite_float(value):
    number = float(value)
    if not math.isfinite(number):
        raise argparse.ArgumentTypeError('coordinates must be finite numbers')
    return number


def quaternion_from_rpy(roll, pitch, yaw):
    """Return an XYZW quaternion for fixed-axis roll, pitch, yaw."""
    sr, cr = math.sin(roll / 2), math.cos(roll / 2)
    sp, cp = math.sin(pitch / 2), math.cos(pitch / 2)
    sy, cy = math.sin(yaw / 2), math.cos(yaw / 2)
    return (sr * cp * cy - cr * sp * sy,
            cr * sp * cy + sr * cp * sy,
            cr * cp * sy - sr * sp * cy,
            cr * cp * cy + sr * sp * sy)


def main():
    parser = argparse.ArgumentParser(
        description='Plan and execute a tool0 pose relative to base_link; metres and radians.')
    for name in ('x', 'y', 'z', 'roll', 'pitch', 'yaw'):
        parser.add_argument(name, type=finite_float)
    args = parser.parse_args()
    rclpy.init()
    node = Node('hc10_pose_goal', parameter_overrides=[
        Parameter('use_sim_time', Parameter.Type.BOOL, True)])
    client = ActionClient(node, MoveGroup, '/move_action')
    try:
        moveit = MoveIt2(
            node=node, joint_names=JOINT_NAMES, base_link_name='base_link',
            end_effector_name='tool0', group_name='manipulator',
            callback_group=ReentrantCallbackGroup(), use_move_group_action=True)
        node.get_logger().info('Waiting for MoveIt and HC10 joint states (30 s maximum)...')
        deadline = time.monotonic() + 30.0
        while rclpy.ok():
            state = moveit.joint_state
            if (client.server_is_ready() and state is not None
                    and set(JOINT_NAMES).issubset(state.name)
                    and node.get_clock().now().nanoseconds > 0):
                break
            if time.monotonic() >= deadline:
                node.get_logger().error('MoveIt, simulation clock or joint states unavailable.')
                return 1
            rclpy.spin_once(node, timeout_sec=0.1)
        if not rclpy.ok():
            return 1
        node.get_logger().info(
            f'tool0 in base_link: XYZ=({args.x}, {args.y}, {args.z}) m; '
            f'RPY=({args.roll}, {args.pitch}, {args.yaw}) rad')
        moveit.move_to_pose(
            position=(args.x, args.y, args.z),
            quat_xyzw=quaternion_from_rpy(args.roll, args.pitch, args.yaw),
            frame_id='base_link', target_link='tool0', cartesian=False)
        # Spin in one thread: pymoveit2 callbacks update the motion state.
        while rclpy.ok() and moveit.query_state() != MoveIt2State.IDLE:
            rclpy.spin_once(node, timeout_sec=0.1)
        error = moveit.get_last_execution_error_code()
        if (rclpy.ok() and moveit.motion_suceeded and error is not None
                and error.val == MoveItErrorCodes.SUCCESS):
            node.get_logger().info('Pose motion completed successfully')
            return 0
        node.get_logger().error('Pose planning or execution failed; check MoveIt logs.')
        return 1
    except KeyboardInterrupt:
        return 130
    finally:
        client.destroy()
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    raise SystemExit(main())
