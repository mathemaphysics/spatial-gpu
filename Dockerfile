FROM nvidia/cuda:11.4.2-cudnn8-devel-ubuntu20.04

# Set up the basic functionality
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get -y install wget sed gawk vim locate \
    && apt-get -y install gcc g++ cmake pkg-config gdb git doxygen graphviz \
    && apt-get -y install libbz2-dev liblz4-dev libssl-dev libzstd-dev catch clang-tidy clang-format libxml2-dev \
    && apt-get -y install libsqlite3-dev sqlite3 libqhull-dev libhdf5-dev mongodb-dev libopenexr-dev libnetcdf-dev libpoppler-dev liblzma-dev unixodbc-dev librasterlite2-dev \
    && apt-get -y install python3 python3-dev python3-dbg python3-pip libeigen3-dev libflann-dev libqhull-dev libusb-1.0 libusb-dev vtk7 libvtk7-dev libboost-all-dev libqt5gui5 qtbase5-dev \
    && apt-get -y install python3-numpy python3-numpy-dbg \
    && apt-get -y install libgeotiff-dev geotiff-bin libopenni2-dev freeglut3 freeglut3-dev libgtk-3-dev gtk-3-examples imagemagick ipython3 tmux libwxgtk3.0-gtk3-dev python3-gi-cairo \
    && sed -ire 's/;Repository=.*$/Repository=\/usr\/lib\/OpenNI2\/Drivers/g' /etc/openni2/OpenNI.ini \
    && python3 -m pip install -U pip \
    && python3 -m pip install meshio pyhull pyproj shapely pandas geopandas matplotlib cookiecutter \
    && python3 -m pip install psycopg2 sqlalchemy

# Clone and build TileDB
WORKDIR /usr/src
RUN git clone https://github.com/TileDB-Inc/TileDB
WORKDIR TileDB/build
RUN git fetch --tags && git checkout 2.2.7
RUN cmake .. -DCMAKE_INSTALL_PREFIX=/usr -DTILEDB_S3=ON -DTILEDB_GCS=ON \
    && make && make install-tiledb && rm -rf /usr/src/TileDB

# Install proj from source
WORKDIR /usr/src
RUN wget https://download.osgeo.org/proj/proj-6.3.1.tar.gz && tar xvf proj-6.3.1.tar.gz
WORKDIR proj-6.3.1
RUN ./configure --prefix=/usr/local && make && make install && make clean && rm -rf /usr/src/proj-6.3.1

# Download and build GDAL
WORKDIR /usr/src
RUN git clone https://github.com/OSGeo/gdal
WORKDIR gdal/gdal
RUN git fetch --tags && git checkout v3.2.1
RUN ./configure --prefix=/usr --with-proj=/usr/local --with-liblzma=yes --with-odbc=/usr && make && make install && make clean && rm -rf /usr/src/gdal

# Download and build GeographicLib
WORKDIR /usr/src
RUN wget https://sourceforge.net/projects/geographiclib/files/distrib/GeographicLib-1.50.1.tar.gz
RUN tar xvf GeographicLib-1.50.1.tar.gz
WORKDIR GeographicLib-1.50.1
RUN ./configure --prefix=/usr && make && make install && make clean && rm -rf /usr/src/GeographicLib-1.50.1
ENV CMAKE_MODULE_PATH=/usr/local/share/cmake/GeographicLib

# Clone and build PDAL
WORKDIR /usr/src
RUN git clone https://github.com/PDAL/PDAL.git
WORKDIR PDAL/build
RUN ln -s /usr/lib/x86_64-linux-gnu/libtiledb.so.2.2 /usr/lib/libtiledb.so.2.2 \
    && ln -s /usr/lib/x86_64-linux-gnu/libtiledb.so /usr/lib/libtiledb.so
RUN git fetch --all && git checkout 2.2.0 # Use this version; bleeding edge is bad
RUN cmake .. -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_PLUGIN_TILEDB=ON -DTILEDB_INCLUDE_DIR=/usr/include -DTILEDB_LIBRARY=/usr/lib/libtiledb.so \
    && make && make install && make clean && rm -rf /usr/src/PDAL

# Install Eigen 3.3.9 for PCL because it needs a fix for CUDA
WORKDIR /usr/src
RUN git clone https://gitlab.com/libeigen/eigen
WORKDIR eigen/build
RUN git fetch --all && git checkout 3.3.9
RUN cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local \
    && make && make install && make clean && rm -rf /usr/src/eigen

# Now that prerequisites are installed, let it rain
WORKDIR /usr/src
RUN git clone https://github.com/PointCloudLibrary/pcl.git
WORKDIR pcl/build
RUN git fetch --all && git checkout pcl-1.11.1
RUN cmake .. -DCMAKE_INSTALL_PREFIX=/usr -DEIGEN_INCLUDE_DIR=/usr/local/include/eigen3 -DOPENNI2_INCLUDE_DIR=/usr/include/openni2 -DOPENNI2_LIBRARY=/usr/lib/libOpenNI2.so -DWITH_OPENMP=ON -DWITH_OPENNI2=ON -DWITH_CUDA=ON -DBUILD_GPU=ON -DBUILD_gpu_surface=ON \
    && make && make install && make clean && rm -rf /usr/src/pcl

# Clone and build LASTools
WORKDIR /usr/src
RUN git clone https://github.com/LAStools/LAStools.git
WORKDIR LAStools/build
RUN cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local && make && make install && make clean && rm -rf /usr/src/LAStools

# Clone and build the OpenKinect Freenect driver for the Kinect
WORKDIR /usr/src
RUN git clone https://github.com/OpenKinect/libfreenect.git
WORKDIR libfreenect/build
RUN git fetch --all && git checkout v0.6.2
RUN cmake .. -DBUILD_OPENNI2_DRIVER=ON && make \
    && cp lib/OpenNI2-FreenectDriver/libFreenectDriver.so /usr/lib/OpenNI2/Drivers/libFreenectDriver.so \
    && chmod 644 /usr/lib/OpenNI2/Drivers/libFreenectDriver.so \
    && ln -s /usr/lib/OpenNI2/Drivers/libFreenectDriver.so /usr/lib/OpenNI2/Drivers/libFreenectDriver.so.0

# Clone and build development version of OpenCV
WORKDIR /usr/src
RUN git clone -b 4.5.4 https://github.com/opencv/opencv_contrib.git
WORKDIR /usr/src
RUN git clone -b 4.5.4 https://github.com/opencv/opencv.git
WORKDIR opencv/build
RUN cmake .. -DCMAKE_INSTALL_PREFIX=/usr \
			 -DWITH_CUDA=ON -DOPENCV_DNN_CUDA=ON -DENABLE_FAST_MATH=ON \
			 -DOPENCV_EXTRA_MODULES_PATH="/usr/src/opencv_contrib/modules" \
                         -DWITH_GDAL=ON -DWITH_EIGEN=ON \
                         -DWITH_OPENMP=ON -DWITH_LAPACK=ON \
                         -DOPENCV_GENERATE_PKGCONFIG=ON \
                         -DWITH_OPENNI2=ON \
        && make \
        && make install

# Clean up the apt cache
RUN apt-get clean

# Start from here
WORKDIR /workspaces

# Set the display to make life easier
ENV LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:/usr/local/lib

