xenserver-hotbackup
===================

xenserver-hotbackup.sh は VMwareのホットバックアップghettoVCB.shのxenserver版です。
xenserverでスナップショットを取得しスナップショットのuuidを指定してexportするだけのものです。

* Free and open-source software: BSD license

# Quick Start

* cfgファイルのUUID(vmno]uuid), xenserverのユーザとパスワード, メールを送る場合はtoとfromを変更してね。

    % chmod +x xenserver-hotbackup.sh
    % vi xenserver-hotbackup.cfg
    % xenserver-hotbackup.sh -f xenserver-hotbackup.cfg
