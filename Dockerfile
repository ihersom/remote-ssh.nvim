FROM ubuntu:22.04

ENV PUBKEY=""

# Install SSH and OpenSSH server
RUN apt-get update && apt-get install -y openssh-server

# Create SSH directory and configure SSH
RUN mkdir /var/run/sshd
RUN echo 'root:password' | chpasswd
# RUN sed -i 's/^PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN echo "PermitRootLogin yes" >> /etc/ssh/sshd_config

RUN mkdir ~/.ssh/ && \
    touch ~/.ssh/authorized_keys && \
    echo "${PUBKEY}" >> ~/.ssh/authorized_keys

RUN mkdir /home/test_dir && \
    touch /home/test_dir/test_file.txt && \
    echo "test contents loaded successfully" >> /home/test_dir/test_file.txt

# Expose port 22
EXPOSE 22

# Start SSH daemon
CMD ["/usr/sbin/sshd", "-D"]
