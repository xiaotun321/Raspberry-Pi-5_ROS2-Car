from setuptools import find_packages, setup

package_name = 'tb6612_car_ros2'

setup(
    name=package_name,
    version='0.0.0',
    packages=find_packages(exclude=['test']),
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='shuaijie',
    maintainer_email='202649427@qq.com',
    description='Raspberry Pi bringup and keyboard teleop for an ESP32-S3 TB6612 car.',
    license='TODO: License declaration',
    extras_require={
        'test': [
            'pytest',
        ],
    },

    # 安装 launch 启动文件
    data_files=[
        ('share/ament_index/resource_index/packages', ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
        ('share/' + package_name + '/launch', ['launch/car_bringup.launch.py']),
    ],    
    entry_points={
        'console_scripts': [
            'keyboard_teleop = tb6612_car_ros2.keyboard_teleop:main',
        ],
    },
)
