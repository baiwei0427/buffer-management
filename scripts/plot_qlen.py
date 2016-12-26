import sys
import matplotlib
matplotlib.use('Agg')

import matplotlib.pyplot as plt

if len(sys.argv) != 3:
    print '%s [input log file] [output figure]' % sys.argv[0]
    sys.exit(1)

log_name = sys.argv[1]
fig_name = sys.argv[2]

log_file = open(log_name, 'r')
lines = log_file.readlines()
log_file.close()

time = []
port_qlen = []

for line in lines:
    arr = line.split()
    if len(arr) < 2 or float(arr[0]) < 1:
        continue

    time.append(float(arr[0]))
    port_qlen.append(int(arr[1]) / 1000)

plt.plot(time, port_qlen)
plt.xlabel('Time (Second)')
plt.ylabel('Port buffer occupancy (KB)')
plt.savefig(fig_name)
