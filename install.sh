#!/bin/sh
mainScriptFileDir="/opt/wifi"
if [ -d "$mainScriptFileDir" ]; then
    echo "Каталог /opt/wifi уже существует. Пропускаем создание..."
else
    mkdir /opt/wifi
fi
if [ -d "/www/js" ]; then
    echo "Каталог /www/js уже существует. Пропускаем создание..."
else
    mkdir /www/js
fi
wget -O /www/js/qrcode.min.js https://cdn.jsdelivr.net/gh/davidshimjs/qrcodejs/qrcode.min.js
#Получим список wifi сетей, который настроены на роутере и выберем из них гостевую
mainScriptFileName="${mainScriptFileDir}/guest_wifi_config.sh"
ssidRegex="s/(.+)=.{0,}'(.+)'.{0,}/\2/"
ssidNames=""
ssidCount=0
ssid=""
while IFS= read -r line; do
 ssidName=$(echo "$line" | sed -r $ssidRegex)
 if [[ "$ssidName" != "" ]]; then
  if [[ "$ssidNames" != *"$ssidName"* ]]; then
   ssidNames="${ssidNames} ${ssidName}"
   ssidCount=$((ssidCount+1))
  fi
 fi
done < <(uci show wireless | grep ".ssid")
if [[ $ssidCount -gt 0 ]]; then
 echo "Список найденых WiFi сетей. Какая из них используется в качестве гостевой?"
 i=0
 for item in $ssidNames; do
  i=$((i+1))
  echo "$i - $item"
 done
 while true; do
  defaultValue=""
  if [[ $ssidCount -eq 1 ]]; then
   defaultValue=" [1]"
  fi
  read -p "Введите номер соответствующий гостевой WiFi сети${defaultValue}: " userOption
  if [[ $ssidCount -eq 1 ]]; then
   userOption=${userOption:-1}
  fi
  if [ "$userOption" -eq "$userOption" ] 2>/dev/null; then
   if [ "$userOption" -le "$ssidCount" ]; then
    i=0
    for item in $ssidNames; do
     i=$((i+1))
     if [ "$i" -eq "$userOption" ]; then
      ssid="$item"
      break 2
     fi
    done
   fi
  fi
  echo "Неправильный ввод. Пожалуйста введите целое число между 1 и $ssidCount"
 done
else
 echo "WiFi сети не найдены. Окончание работы"
 exit 1
fi
isHidden="true"
while true; do
  read -p "Данная сеть является скрытой - (1) или отображается в списке WiFi сетей - (2)? [1]: " userOption
  userOption=${userOption:-1}
  if [ "$userOption" -eq "$userOption" ] 2>/dev/null; then
   if [ $userOption -eq 1 ]; then
    isHidden="true"
    break
   fi
   if [ $userOption -eq 2 ]; then
    isHidden="false"
    break
   fi
  fi
  echo "Неправильный ввод. Пожалуйста введите 1 или 2"
done
cipherType="WPA"
while true; do
  read -p "Данная сеть использует шифрование WPA - (1) или WEP - (2)? [1]: " userOption
  userOption=${userOption:-1}
  if [ "$userOption" -eq "$userOption" ] 2>/dev/null; then
   if [ $userOption -eq 1 ]; then
    cipherType="WPA"
    break
   fi
   if [ $userOption -eq 2 ]; then
    cipherType="WEP"
    break
   fi
  fi
  echo "Неправильный ввод. Пожалуйста введите 1 или 2"
done
keyChangeInterval=15
while true; do
  read -p "Период действия пароля гостевой WiFi сети в минутах [15]: " userOption
  userOption=${userOption:-15}
  if [ "$userOption" -eq "$userOption" ] 2>/dev/null; then
   if [[ $userOption -ge 1 &&  $userOption -le 30 ]]; then
    keyChangeInterval=$((userOption))
    break
   fi
  fi
  echo "Неправильный ввод. Пожалуйста введите целое число от 1 до 30"
done
regex="s/(.+)\.ssid.{0,}=.{0,}'(.+)'.{0,}/\1/" #regex, который поможет нам найти названия параметров для конфигурирования WiFi сети
paramNames=""
while IFS= read -r line; do
 paramName=$(echo "$line" | sed -r $regex)
 if [[ "$paramName" != "" ]]; then
  if [[ "$paramNames" != *"$paramName"* ]]; then
   paramNames="${paramNames} ${paramName}"
  fi
 fi
done < <(uci show wireless | grep ".ssid='$ssid'")
configureKeyCommands=""
for item in $paramNames; do
 if [[ "$configureKeyCommands" != "" ]]; then
  configureKeyCommands="$configureKeyCommands"$'\n'
 fi
 configureKeyCommands="${configureKeyCommands}uci set $item.key=\$wifiPass"
done
lastRunTimeFileName="/dev/shm/$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)" 
#Создаем скрипт, который будет запускаться cron'ом, настраивать параметры WiFi и обновлять страницу, которая отображает QR код для конфигурирования сети
cat <<EOF1 > $mainScriptFileName
#!/bin/sh
#Проверим, есть ли файл javascript, который создает QR код. Если файла нет, создадим в ОЗУ и создадим ссылку на него в каталоге /www/js
if [ ! -f "/dev/shm/genqr.js" ]; then
 touch /dev/shm/genqr.js
 ln -s /dev/shm/genqr.js /www/js/genqr.js
fi
currentDate=$(date +%s)
#получим из файла последнее время смены пароля скриптом (если файл есть)
if [ -f "$lastRunTimeFileName" ]; then
    lastRunTime=\$(cat "$lastRunTimeFileName")
else
    lastRunTime=0
fi
diffMinutes=\$(( (currentDate - lastRunTime) / 60 ))
if [ \$diffMinutes -lt $keyChangeInterval ]; then #если интервал еще не достигнут, ничего больше не делаем, выходим
 exit 0
fi
echo \$currentDate > "$lastRunTimeFileName"
wifiPass=\$(openssl rand -base64 12)
now=\$(date +%s)
expTime=\$((now + $keyChangeInterval * 60))
expTimeStr=\$(date -d "@\$expTime" +"%Y-%m-%dT%H:%M:%S%z")
cat <<EOF > /www/js/genqr.js
new QRCode(document.getElementById("qrcode"), {text: "WIFI:S:$ssid;T:$cipherType;P:\$wifiPass;H:$isHidden;;", correctLevel: QRCode.CorrectLevel.L});
function refreshTimer() {
 const e = document.getElementById('expTime');
 if (e) {
  const wifiExpTime = new Date("\$expTimeStr");
  const currentTime = new Date();
  const diffMs = wifiExpTime - currentTime;
  if (diffMs > 0) {
   let totalSeconds = Math.floor(diffMs / 1000);
   const days = Math.floor(totalSeconds / (24 * 60 * 60));
   totalSeconds = (totalSeconds - days * 24 * 60 * 60)
   const hours = Math.floor(totalSeconds / (60 * 60));
   totalSeconds = (totalSeconds - hours * 60 * 60)
   const minutes = Math.floor(totalSeconds / 60);
   const seconds = totalSeconds % 60;
   e.innerHTML = 'Осталось: ' + (days > 0 ? days + "д. " : "") + hours.toString().padStart(2, '0') + ":" + minutes.toString().padStart(2, '0') + ":" + seconds.toString().padStart(2, '0');
   setTimeout(refreshTimer, 1000);
  } else {
   e.innerHTML = 'Истек срок действия<br>Дождитесь обновления';
   setTimeout(reloadPage, 5000);
  }
 }
}
function reloadPage() {
 location.reload();
}
refreshTimer();
EOF
$configureKeyCommands
uci commit wireless
wifi
EOF1
cat <<EOF > /www/guest.html
<html lang="ru-RU">
<head>
 <meta charset="UTF-8">
 <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
 <title>Guest wifi QR</title>
</head>
<body style="font-family:arial;">
<script src="js/qrcode.min.js"></script>
<div>
 <div style="display: flex; justify-content: center; align-items: center; height: 80vh; flex-direction: column">
  <div style="display: flex; justify-content: center; align-items: center; text-align: center; height: 150px;">
   <span style="font-size: 22px; font-weight: bold;">
    &laquo;Гостевой&raquo; WiFi<br>
    Для подключения<br>
    наведите камеру смартфона<br>на QR код
   </span>
  </div>
  <div id="qrcode"></div>
  <div style="display: flex; justify-content: center; align-items: center; text-align: center; height: 80px;">
   <span style="font-size: 22px; font-weight: bold;" id="expTime" data-exp-time="2026-04-29 14:30:00"></span>
  </div>
 </div>
</div>
<script src="js/genqr.js"></script>
</body>
</html>
EOF
chmod +x $mainScriptFileName
JOB="* * * * * $mainScriptFileName"
(crontab -l 2>/dev/null | grep -Fv "$mainScriptFileName"; echo "$JOB") | crontab -
cat <<EOF > uninstall.sh
rm /www/guest.html
rm /www/js/qrcode.min.js
rm /www/js/genqr.js
rm /dev/shm/genqr.js
rm $mainScriptFileName
rm $lastRunTimeFileName
crontab -l | grep -v '$mainScriptFileName' | crontab -
EOF
chmod +x uninstall.sh
$mainScriptFileName
echo "Установка завершена. Для отображения QR кода подключения к гостевому WiFi перейдите с устройства, подключенного к домашней сети по ссылке http://{IP адрес роутера}/guest.html (рекомендуем добавить в закладки)."
