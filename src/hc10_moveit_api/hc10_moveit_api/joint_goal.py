import time
import rclpy

from threading import Thread

from rclpy.node import Node
from rclpy.callback_groups import ReentrantCallbackGroup
from rclpy.executors import MultiThreadedExecutor
from rclpy.parameter import Parameter

from pymoveit2 import MoveIt2


JOINT_NAMES = [
    "joint_1_s",
    "joint_2_l",
    "joint_3_u",
    "joint_4_r",
    "joint_5_b",
    "joint_6_t",
]


def main():
    rclpy.init()

    node = Node(
        "hc10_pymoveit2_api",
        parameter_overrides=[
            Parameter("use_sim_time", Parameter.Type.BOOL, True),
        ],
        automatically_declare_parameters_from_overrides=True,
    )

    node.declare_parameter("mode", "joint")

    node.declare_parameter("j1", 0.30)
    node.declare_parameter("j2", -0.25)
    node.declare_parameter("j3", 0.20)
    node.declare_parameter("j4", 0.00)
    node.declare_parameter("j5", 0.15)
    node.declare_parameter("j6", 0.00)

    node.declare_parameter("x", 0.5)
    node.declare_parameter("y", 0.0)
    node.declare_parameter("z", 0.6)

    node.declare_parameter("qx", 0.0)
    node.declare_parameter("qy", 0.0)
    node.declare_parameter("qz", 0.0)
    node.declare_parameter("qw", 1.0)

    callback_group = ReentrantCallbackGroup()

    moveit2 = MoveIt2(
        node=node,
        joint_names=JOINT_NAMES,
        base_link_name="base_link",
        end_effector_name="tool0",
        group_name="manipulator",
        callback_group=callback_group,
        use_move_group_action=True,
    )

    executor = MultiThreadedExecutor(num_threads=2)
    executor.add_node(node)

    executor_thread = Thread(target=executor.spin, daemon=True)
    executor_thread.start()

    node.get_logger().info("Waiting for MoveIt action server...")
    time.sleep(3.0)

    mode = node.get_parameter("mode").value

    if mode == "joint":
        joint_target = [
            node.get_parameter("j1").value,
            node.get_parameter("j2").value,
            node.get_parameter("j3").value,
            node.get_parameter("j4").value,
            node.get_parameter("j5").value,
            node.get_parameter("j6").value,
        ]

        node.get_logger().info(
            f"Joint target: {joint_target}"
        )

        moveit2.move_to_configuration(
            joint_positions=joint_target,
            joint_names=JOINT_NAMES,
        )

    elif mode == "pose":
        position = [
            node.get_parameter("x").value,
            node.get_parameter("y").value,
            node.get_parameter("z").value,
        ]

        quaternion = [
            node.get_parameter("qx").value,
            node.get_parameter("qy").value,
            node.get_parameter("qz").value,
            node.get_parameter("qw").value,
        ]

        node.get_logger().info(
            f"Pose target: position={position}, quaternion={quaternion}"
        )

        moveit2.move_to_pose(
            position=position,
            quat_xyzw=quaternion,
            target_link="tool0",
            frame_id="base_link",
        )

    else:
        node.get_logger().error(
            "Invalid mode. Use mode:=joint or mode:=pose"
        )
        rclpy.shutdown()
        return

    success = moveit2.wait_until_executed()

    if success:
        node.get_logger().info("Motion completed successfully")
    else:
        node.get_logger().error("Motion failed")

    rclpy.shutdown()
    executor_thread.join(timeout=1.0)


if __name__ == "__main__":
    main()
