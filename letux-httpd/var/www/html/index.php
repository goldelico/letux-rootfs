<h1>Welcome to Letux httpd installation</h1>
<p>Here you have PHP (letux-httpd)<?php if(file_exists("/usr/bin/mysql")) echo " and MySQL/MariaDB (letux-amp)"; ?></p>
<p><a href="https://www.php.net/manual/">PHP Manual</a></p>

<?php

$KERNEL=shell_exec("uname -a");

if(file_exists("/proc/device-tree/model"))
	$DEVICE=file_get_contents("/proc/device-tree/model");
else
	$DEVICE=shell_exec("uname -n");

if(file_exists("/etc/debian_version"))
	$OS="Debian ".file_get_contents("/etc/debian_version");
else
	$OS=shell_exec("uname -sr");
?>

<p>Device: <?php echo htmlentities($DEVICE); ?></p>
<p>Kernel: <?php echo htmlentities($KERNEL); ?></p>
<p>OS: <?php echo htmlentities($OS); ?></p>

<?php

phpinfo();

?>