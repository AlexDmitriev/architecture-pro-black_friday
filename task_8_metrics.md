# <a name="_b7urdng99y53"></a>**Набор метрик для отслеживания состояния шардов и механизмы автоматического распределения данных** 
#### <a name="_hjk0fkfyohdk"></a>**Дмитриев А.В.**
#### <a name="_uanumrh8zrui"></a>**03.03.2026**

## <a name="_3bfxc9a45514"></a>**Набор метрик для отслеживания состояния шардов**


### Метрика 1: Распределение документов по шардам

* Объем данных 
* Количество документов 
* Количество чанков в шарде

```
db.products.getShardDistribution()
```

Метрика позволяет выбрать "горячий" шард при отклонениях >20% от среднего.

-------------

### Метрика 2: Операционные (нагрузочные) метрики

2.1 Статистика операций по шардам
```
db.adminCommand({ shardConnPoolStats: 1 })
```

2.2 Метрики по каждому из шардов

* метрики по операциям (insert, update, delete)
* текущая очередь в шарде
* количество подключений к шарду

```
db.adminCommand({ serverStatus: 1, opcounters: 1, opcountersRepl: 1, metrics: 1 })
```

2.3. Среднее время ответа шарда (latency performance)

* анлиз среднего ответа на шарде и отклонение от среднего ответа по кластеру

```
db.setProfilingLevel(1, { slowms: 100 })

db.system.profile.aggregate([
  { $match: { op: { $in: ["query", "update", "remove"] } } },
  { $group: {
    _id: "$shard",
    avgMillis: { $avg: "$millis" },
    maxMillis: { $max: "$millis" },
    count: { $sum: 1 }
  }}
])
```

2.4 Метрики горячих ключей (Hotspots)

* анализ частоты запросов по категориям, если какая-то из категорияй выделяется, это дисбаланс

```
db.system.profile.aggregate([
  { $match: { 
    op: "query",
    ns: "shop.products",
    "command.filter.category": { $exists: true }
  }},
  { $group: {
    _id: "$command.filter.category",
    count: { $sum: 1 },
    avgMillis: { $avg: "$millis" }
  }},
  { $sort: { count: -1 } },
  { $limit: 10 }
])
```

--------------

## <a name="_3bfxc9a45514"></a>**Механизмы автоматического распределения данных**

1. Автоматическая (Built-in) балансировка чанков 

```
// включение балансировщика
sh.setBalancerState(true)

// настройка периода балансировки (в данном случае - ночью)
db.settings.updateOne(
  { _id: "balancer" },
  { $set: { 
    activeWindow: { 
      start: "02:00", 
      stop: "06:00" 
    },
    secondaryThrottle: 1, 
    _waitForDelete: true 
  }},
  { upsert: true }
)

// настройка порога для миграции
db.settings.updateOne(
  { _id: "balancer" },
  { $set: { 
    threshold: 4 
  }}
)
```

2. Ручное перераспределение для горячих категорий

```
// определение горячих категорий
const hotCategories = db.aggregate([
  { $match: { "stock.quantity": { $gt: 0 } } },
  { $group: { _id: "$category", count: { $sum: 1 } } },
  { $sort: { count: -1 } },
  { $limit: 5 }
]).toArray()

// сплит чанков горячих категорий на более мелкие
hotCategories.forEach(cat => {
  // Находим чанки для категории
  const chunks = db.getSiblingDB("config").chunks.find({
    ns: "shop.products",
    "min.category": cat._id
  })
  
  chunks.forEach(chunk => {
    // сплитим на более мелкие части (например, по цене)
    if (chunk.max.price - chunk.min.price > 1000) {
      sh.splitAt("shop.products", {
        category: cat._id,
        price: chunk.min.price + 500
      })
    }
  })
})
```