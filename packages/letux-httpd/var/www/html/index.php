<h1>Welcome to Letux httpd installation</h1>

<p>Here you have PHP (letux-http)<?php if(file_exists("/usr/bin/mysql")) echo " and MySQL/MariaDB (letux-amp)"; ?></p>
<p>Device: <?php htmlentities(system("cat /proc/device-tree/model")); ?></p>
<p>Kernel: <?php htmlentities(system("/bin/uname -a")); ?></p>
<p>Debian: <?php htmlentities(system("cat /etc/debian_version")); ?></p>

<?php

phpinfo();

?>