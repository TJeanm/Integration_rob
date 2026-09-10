import sys
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
    if len(sys.argv) != 7:
        print()
        print("Usage:")
        print("  joint_goal j1 j2 j3 j4 j5 j6")
        print()
        print("Example:")
        print("  joint_goal 0.3 -0.25 0.2 0.0 0.15 0.0")
        print()
        sys.exit(1)

    try:
        joint_target = [float(value) for value in sys.argv[1:7]]
    except ValueError:
        print("ERROR: all joint coordinates must be numbers.")
        sys.exit(1)

    rclpy.init()

    node = Node(
        "hc10_pymoveit2_api",
        parameter_overrides=[
            Parameter(
                "use_sim_time",
                Parameter.Type.BOOL,
                True,
            )
        ],
    )

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

    executor_thread = Thread(
        target=executor.spin,
        daemon=True,
    )
    executor_thread.start()

    node.get_logger().info("Waiting for MoveIt...")
    time.sleep(3.0)

    node.get_logger().info(
        "Joint goal:"
        f" j1={joint_target[0]:.3f}"
        f" j2={joint_target[1]:.3f}"
        f" j3={joint_target[2]:.3f}"
        f" j4={joint_target[3]:.3f}"
        f" j5={joint_target[4]:.3f}"
        f" j6={joint_target[5]:.3f}"
    )

    moveit2.move_to_configuration(
        joint_positions=joint_target,
        joint_names=JOINT_NAMES,
    )

    success = moveit2.wait_until_executed()

    if success:
        node.get_logger().info("Motion completed successfully")
    else:
        node.get_logger().error("Motion failed")

    rclpy.shutdown()
    executor_thread.join(timeout=1.0)


if __name__ == "__main__":
    main()
