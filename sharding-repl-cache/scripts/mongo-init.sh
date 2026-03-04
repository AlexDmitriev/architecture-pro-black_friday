#!/bin/bash
set -e

###
# Инициализируем бд
###
echo "Init configSrv"
docker exec -i configSrv mongosh --port 27010 <<EOF
rs.initiate(
  {
    _id : "config_server",
       configsvr: true,
    members: [
      { _id : 0, host : "configSrv:27010" }
    ]
  }
);
EOF
sleep 5
echo "Init shard1"
docker exec -i shard11 mongosh --port 27011 <<EOF
rs.initiate(
    {
      _id : "shard1",
      members: [
        { _id : 0, host : "shard11:27011" },
        { _id : 1, host : "shard12:27012" },
        { _id : 2, host : "shard13:27013" }
      ]
    }
);
EOF
sleep 5
echo "Init shard2"
docker exec -i shard21 mongosh --port 27014 <<EOF
rs.initiate(
    {
      _id : "shard2",
      members: [
        { _id : 0, host : "shard21:27014" },
        { _id : 1, host : "shard22:27015" },
        { _id : 2, host : "shard23:27016" }
      ]
    }
  );
EOF
sleep 5
echo "Init router"
docker compose exec -T mongodb1 mongosh --port 27020 <<EOF
sh.addShard( "shard1/shard11:27011,shard12:27012,shard13:27013");
sh.addShard( "shard2/shard21:27014,shard22:27015,shard23:27016");
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } )
use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})
EOF
echo "Docs in shard1"
docker exec -i shard11 mongosh --port 27011 <<EOF
use somedb;
db.helloDoc.countDocuments()
EOF
echo "Docs in shard2"
docker exec -i shard21 mongosh --port 27014 <<EOF
use somedb;
db.helloDoc.countDocuments()
EOF
