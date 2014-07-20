
    sudo echo "begin"
    cd /tmp


    git clone https://github.com/Eonblast/Emysql
    cd Emysql && make

    cd /tmp
    git clone git://github.com/processone/ejabberd-contrib.git
    cd ejabberd-contrib && git checkout 2.1.x
    cp ../Emysql/ebin/* ejabberd-dev/ebin/
    git clone https://github.com/schemacs/mod_log_chat_mysql5.git
    cd mod_log_chat_mysql5/ && ./build.sh

    cd /tmp/ejabberd-contrib
    sudo cp mod_log_chat_mysql5/ebin/mod_log_chat_mysql5.beam /usr/lib/ejabberd/ebin
    sudo cp ../Emysql/ebin/* /usr/lib/ejabberd/ebin

    {mod_log_chat_mysql5, [{server, "127.0.0.1"}, {db, "im"}, {user, "root"}, {password, ""}, {pool_size, 1}, {encoding, utf8}]},

    CREATE DATABASE IF NOT EXISTS im CHARACTER SET utf8;
    USE im;
    CREATE TABLE mod_log_chat_mysql5 (
       id INT AUTO_INCREMENT PRIMARY KEY,
       fromJid VARCHAR(255) NOT NULL,
       toJid VARCHAR(255) NOT NULL,
       sentDate TIMESTAMP NOT NULL,
       body TEXT,
       type VARCHAR(10)
    ) ENGINE=MyISAM CHARACTER SET utf8;

    sudo ejabberdctl register admin chat.example.com test
    sudo ejabberdctl register test chat.example.com test
    sudo apt-get install --yes sendxmpp
    sendxmpp -v -u admin -p test -j chat.example.com -s 'wake up' test@chat.example.com
    sendxmpp -v -u test -p test -j chat.example.com -s 'wake up' admin@chat.example.com
