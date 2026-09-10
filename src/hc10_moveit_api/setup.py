from setuptools import find_packages, setup

package_name = 'hc10_moveit_api'

setup(
    name=package_name,
    version='0.0.0',
    packages=find_packages(exclude=['test']),
    data_files=[
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='theo',
    maintainer_email='theo.jeanmart@univ-tlse.fr.com',
    description='TODO: Package description',
    license='TODO: License declaration',
    extras_require={
        'test': [
            'pytest',
        ],
    },
    entry_points={
        'console_scripts': [
		'joint_goal = hc10_moveit_api.joint_goal:main',
        'pose_goal = hc10_moveit_api.pose_goal:main',
        ],
    },
)
