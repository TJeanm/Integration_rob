from setuptools import find_packages, setup

package_name = 'hc10_mfja_control_adapter'
setup(
    name=package_name,
    version='0.1.0',
    packages=find_packages(),
    data_files=[
        ('share/ament_index/resource_index/packages', ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='MFJA',
    maintainer_email='maintainer@example.com',
    description='FollowJointTrajectory adapter for the MFJA HC10 Gazebo interface.',
    license='Apache-2.0',
    entry_points={'console_scripts': [
        'hc10_control_adapter = hc10_mfja_control_adapter.adapter:main',
    ]},
)
