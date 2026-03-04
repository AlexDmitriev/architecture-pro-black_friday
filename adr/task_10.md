# <a name="_b7urdng99y53"></a>**Миграция на Cassandra: модель данных, стратегии репликации и шардирования** 
#### <a name="_hjk0fkfyohdk"></a>**Дмитриев А.В.**
#### <a name="_uanumrh8zrui"></a>**04.03.2026**

## <a name="_3bfxc9a45514"></a>**Области применения Cassandra**

В первую очередь стоит использовать Cassandra для критически-важных данных:
* корзины пользователей (с разделением на корзины авторизованных и неавторизованных пользователей)
* заказы пользователей
* складские остатки товаров

Основное преимущество Cassandra при работе с реплицированными данными - доступ к данным по известному ключу (user_id, session_id, order_id, product_id), что реализуемо для выбранного списка. 

Перенос в Cassandra каталога товаров видится нецелесообразным, т.к. используя category в качестве partition key, товары будут распределяться по нодам неравномерно, образовывая "горячие" ноды. 


## <a name="_3bfxc9a45514"></a>**Концептуальная модель для выбранных сущностей**

### Корзины неавторизованных пользователей

```
CREATE TABLE session_carts (
    session_id uuid, 
    product_id uuid, 
    product_quantity int,
    status string,
    created_at timestamp,
    updated_at timestamp,
    ttl int,
    PRIMARY KEY ((session_id), product_id)
);
```
- partition key - session_id
- clustering key - product_id

-----------------

### Корзины авторизованных пользователей

```
CREATE TABLE user_carts (
    user_id uuid,
    product_id uuid,
    product_quantity int,
    status string,
    created_at timestamp,
    updated_at timestamp,
    ttl int,
    PRIMARY KEY ((user_id), product_id, created_at)
);
```

- partition key - user_id
- clustering key - product_id


-----------------

### Заказы

```
CREATE TABLE orders (
    user_id uuid,
    order_id uuid,    
    product_id uuid,
    product_quantity int,
    status string,
    created_at timestamp,
    updated_at timestamp,
    location string,
    PRIMARY KEY ((user_id), order_id, product_id)
);
```

- partition key - user_id
- clustering keys - order_id, product_id, 

-----------------

### Складские остатки:

```
CREATE TABLE product_stock (
    product_id uuid,
    location string,
    product_quantity COUNTER,
    created_at timestamp,
    updated_at timestamp,
    PRIMARY KEY ((product_id), location)
);
```

- partition key - product_id
- clustering key - location

-----------------

Как уже было сказано выше, выбор соотвествующих partition key делает распределение данных по шардам относительно равномерным, а выбор clustering keys добавляет сортировку записей исходя из бизнес-логики :
- сортировка продуктов внутри корзины по дате добавления
- сортировка продуктов в заказе по заказу
- сортировка стоков (наличия на складе) продукта по складам

и т.д. Главный риск - наличие популярного продукта (например при распродаже), где запросы к складским остатками будут создавать дисбаланс. 


## <a name="_3bfxc9a45514"></a>**Стратегии обеспечения целостности**

|**№**|**Компонент**|**Стратегия**|**Комментарий**|
| :-: | :- | :- | :- |
|C1|Заказ, Корзина|Hinted Handoff|Стратегия предоставляет возможность показывать актуальный заказ с минимальной latency (не нужно ждать подтверждения от всех нод) для данных, которые актуальны в real-time бизнес-задачах - оформление заказа.|
|C2|Наличие продукта на складе|Read Repair|При списании остатков важна консистентность данных, т.к. система не должна позволять заказывать закончившийся товар. Дополнительно, при чтении из нескольких реплик координатор сравнивает данные и, если находит расхождения, обновляет устаревшие значения.|
|C1, C2|Заказ, Корзина, Наличие продукта на складе|Anti-Entropy Repair|Периодический запуск синхронизации данных для всех типов сущности, запускается в ручном режиме при отсутсвии серьезных нагрузок на систему|

