import math
import threading
import time

import rclpy
from control_msgs.action import FollowJointTrajectory
from control_msgs.msg import JointTolerance
from rclpy.action import ActionServer, CancelResponse, GoalResponse
from rclpy.callback_groups import ReentrantCallbackGroup
from rclpy.executors import MultiThreadedExecutor
from rclpy.node import Node
from sensor_msgs.msg import JointState
from trajectory_msgs.msg import JointTrajectory, JointTrajectoryPoint


JOINTS = [
    'joint_1_s', 'joint_2_l', 'joint_3_u',
    'joint_4_r', 'joint_5_b', 'joint_6_t',
]


class Hc10MfjaControlAdapter(Node):
    def __init__(self):
        super().__init__('hc10_mfja_control_adapter')
        self.declare_parameter('action_name', '/yaskawa_hc10_1/follow_joint_trajectory')
        self.declare_parameter('command_topic', '/yaskawa_hc10_1/joint_trajectory')
        self.declare_parameter('joint_state_topic', '/yaskawa_hc10_1/joint_states')
        self.declare_parameter('goal_tolerance', 0.03)
        self.declare_parameter('state_timeout', 2.0)
        self.declare_parameter('execution_timeout_margin', 5.0)

        self._positions = {}
        self._state_time = 0.0
        self._lock = threading.Lock()
        group = ReentrantCallbackGroup()
        self._publisher = self.create_publisher(
            JointTrajectory, self.get_parameter('command_topic').value, 10)
        self.create_subscription(
            JointState, self.get_parameter('joint_state_topic').value,
            self._state_callback, 20, callback_group=group)
        self._server = ActionServer(
            self, FollowJointTrajectory,
            self.get_parameter('action_name').value,
            execute_callback=self._execute,
            goal_callback=self._goal_callback,
            cancel_callback=self._cancel_callback,
            callback_group=group,
        )
        self.get_logger().info(
            f"Ready on {self.get_parameter('action_name').value}; forwarding to "
            f"{self.get_parameter('command_topic').value}")

    def _state_callback(self, msg):
        with self._lock:
            self._positions.update(dict(zip(msg.name, msg.position)))
            self._state_time = time.monotonic()

    @staticmethod
    def _seconds(duration):
        return duration.sec + duration.nanosec * 1e-9

    def _goal_callback(self, goal):
        trajectory = goal.trajectory
        if set(trajectory.joint_names) != set(JOINTS) or len(trajectory.joint_names) != len(JOINTS):
            self.get_logger().warning('Rejected trajectory: joint names must match the six HC10 joints')
            return GoalResponse.REJECT
        if not trajectory.points:
            self.get_logger().warning('Rejected empty trajectory')
            return GoalResponse.REJECT
        previous = -1.0
        for point in trajectory.points:
            if len(point.positions) != len(JOINTS):
                self.get_logger().warning('Rejected trajectory: invalid point dimension')
                return GoalResponse.REJECT
            stamp = self._seconds(point.time_from_start)
            if stamp < previous:
                self.get_logger().warning('Rejected trajectory: time_from_start is not monotonic')
                return GoalResponse.REJECT
            previous = stamp
        return GoalResponse.ACCEPT

    def _cancel_callback(self, _goal_handle):
        return CancelResponse.ACCEPT

    def _snapshot(self):
        with self._lock:
            return dict(self._positions), self._state_time

    def _publish_hold(self):
        positions, _ = self._snapshot()
        if not all(name in positions for name in JOINTS):
            return
        hold = JointTrajectory()
        hold.joint_names = list(JOINTS)
        point = JointTrajectoryPoint()
        point.positions = [positions[name] for name in JOINTS]
        point.time_from_start.nanosec = 100_000_000
        hold.points = [point]
        self._publisher.publish(hold)

    @staticmethod
    def _tolerance_map(requested, default):
        values = {name: default for name in JOINTS}
        for tolerance in requested:
            if tolerance.name in values and tolerance.position > 0.0:
                values[tolerance.name] = tolerance.position
        return values

    def _execute(self, goal_handle):
        result = FollowJointTrajectory.Result()
        positions, state_time = self._snapshot()
        state_timeout = float(self.get_parameter('state_timeout').value)
        if not all(name in positions for name in JOINTS) or time.monotonic() - state_time > state_timeout:
            result.error_code = FollowJointTrajectory.Result.INVALID_GOAL
            result.error_string = 'No complete, fresh HC10 joint state available'
            goal_handle.abort()
            return result

        trajectory = goal_handle.request.trajectory
        self._publisher.publish(trajectory)
        duration = self._seconds(trajectory.points[-1].time_from_start)
        requested_goal_time = self._seconds(goal_handle.request.goal_time_tolerance)
        timeout = duration + max(
            requested_goal_time,
            float(self.get_parameter('execution_timeout_margin').value))
        tolerance = self._tolerance_map(
            goal_handle.request.goal_tolerance,
            float(self.get_parameter('goal_tolerance').value))
        target = dict(zip(trajectory.joint_names, trajectory.points[-1].positions))
        # La trajectoire est cadencée par Gazebo. Sur une VM en rendu logiciel,
        # le temps simulé avance moins vite que le temps mural; un timeout mural
        # annulerait alors un mouvement pourtant sain avant sa fin.
        start_sim = self.get_clock().now().nanoseconds * 1e-9

        while rclpy.ok():
            if goal_handle.is_cancel_requested:
                self._publish_hold()
                goal_handle.canceled()
                result.error_code = FollowJointTrajectory.Result.SUCCESSFUL
                result.error_string = 'Trajectory canceled; hold command sent'
                return result

            positions, state_time = self._snapshot()
            if time.monotonic() - state_time > state_timeout:
                goal_handle.abort()
                result.error_code = FollowJointTrajectory.Result.INVALID_GOAL
                result.error_string = 'Joint state feedback timed out'
                return result

            feedback = FollowJointTrajectory.Feedback()
            feedback.joint_names = list(trajectory.joint_names)
            feedback.actual.positions = [positions.get(name, math.nan) for name in trajectory.joint_names]
            feedback.desired.positions = [target[name] for name in trajectory.joint_names]
            feedback.error.positions = [
                target[name] - positions.get(name, target[name]) for name in trajectory.joint_names]
            goal_handle.publish_feedback(feedback)

            elapsed_sim = self.get_clock().now().nanoseconds * 1e-9 - start_sim
            if elapsed_sim >= duration:
                if all(abs(positions[name] - target[name]) <= tolerance[name] for name in JOINTS):
                    goal_handle.succeed()
                    result.error_code = FollowJointTrajectory.Result.SUCCESSFUL
                    result.error_string = 'Final position reached'
                    return result
            if elapsed_sim > timeout:
                goal_handle.abort()
                result.error_code = FollowJointTrajectory.Result.GOAL_TOLERANCE_VIOLATED
                result.error_string = 'Final position was not reached before timeout'
                return result
            time.sleep(0.05)

        goal_handle.abort()
        result.error_code = FollowJointTrajectory.Result.INVALID_GOAL
        result.error_string = 'ROS shutdown during execution'
        return result


def main(args=None):
    rclpy.init(args=args)
    node = Hc10MfjaControlAdapter()
    executor = MultiThreadedExecutor(num_threads=2)
    executor.add_node(node)
    try:
        executor.spin()
    except KeyboardInterrupt:
        pass
    finally:
        executor.shutdown()
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()
