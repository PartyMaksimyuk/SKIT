USE [Mobile_Skit]
GO
/****** Object:  StoredProcedure [dbo].[Report_USER13309]    Script Date: 29.08.2016 19:02:00 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
--
--	Региональный отчет
--
ALTER procedure [dbo].[Report_USER13309]
	@bDate datetime
AS
Declare @edate datetime

Set Nocount On
SET DATEFORMAT YMD
Set @bDate = dbo.dateonly(@bDate)
set @eDate=@bDate
Set @eDate = dbo.dateonly(@eDate)
Set @eDate = dateadd(Hour, 23, @eDate)
Set @eDate = dateadd(minute, 59, @eDate)
Set @eDate = dateadd(second, 59, @eDate)

Exec DL_Report_AddPeriod N'#Filter', @bDate, @eDate
Create Table #flt
(
	[Type]	int	not null
,	Id		int	null
,	Id2		int	null
,	Id3		int	null
,	Id4		int	null
,	Id5		int	null
,	IdStr		nvarchar(3000) collate database_default null
,	DatJoin 	nvarchar(4000) collate database_default null
)

INSERT INTO  #flt ( [type], id,id2,id3,id4,id5,idstr )
SELECT [type], id,id2,id3,id4,id5,idstr
FROM #Filter

Create Table #tVisits
(	OwnerDistId		Int,
	MasterFid		Int,
	Fid				Int,
	vDate			DateTime,
	DateBegin		DateTime,
	DateEnd			DateTime,
	OtkazStr		NVarChar(255),
	PDA				Int,
	vDateOnly		DateTime
)

Exec DL_Get_Visits N'1;2;3;4;5;6;12;13;14', N'#tVisits', N'#flt'

CREATE TABLE #tfaces
(	Fid				INT,
	fName			NVARCHAR(255),
	ExId			NVARCHAR(255),
	fType			INT,
	OwnerDistId		INT,
	fAddress		NVARCHAR(100)
)
--
--	предварительная очистка таблицы фильтров
--	обработка информации по визитам
--

TRUNCATE TABLE #flt
--
--	добавление фильтров
--
INSERT INTO  #flt ( [type], id)
	SELECT 440003 AS [Type], MasterFid
	FROM #tVisits
UNION
	SELECT 440008 AS [Type], Fid
	FROM #tVisits
--
--	добавление фильтров по владельцам
--
INSERT INTO  #flt ( [type], id, id2 )
	SELECT DISTINCT 6 AS [Type], 2 AS id, OwnerDistId
	FROM #tVisits
--
--	фильтруем таблицу tfaces по выбранным пораметрам
--
EXEC DL_Get_Faces N'1;2;3;17;21;20;6', N'#tFaces', N'#flt'

--CREATE INDEX tmp_#tFaces On #tFaces ( Fid)

--
--	добавление колонок
--
ALTER TABLE #tFaces ADD gorod NVARCHAR(100), street NVARCHAR(100), dom NVARCHAR(100), nomerTT NVARCHAR(50)

EXEC dbo.ParseAddress
--
--	обработка данных по документам. убираем старую фильтрацию
--
TRUNCATE TABLE #flt
EXEC DL_Report_AddPeriod N'#flt', @bDate, @eDate

--
--	вставка фильтров по типам документов
--
INSERT INTO #flt([Type], Id)
		SELECT 440011 AS [Type], 611
	UNION
		SELECT 440011 AS [Type], 612
	UNION
		SELECT 440011 AS [Type], 608
	UNION
		SELECT 440011 AS [Type], 230
	UNION
		SELECT 440011 AS [Type], 610
	UNION
		SELECT 440011 AS [Type], 607
	UNION
		SELECT 440011 AS [Type], 206
	UNION
		SELECT 440200 AS [Type], 1

--
--	отфильтрованная таблица с документами
--
CREATE TABLE #tDocuments
(
	MasterFid INT,
	OrId INT,
	OrDate DATETIME,
	OwnerDistId INT,
	mFid INT,
	Ufid INT,
	OrType INT,
	MasterDocId INT,
	orComment NVARCHAR(250)
)
--
--	фильтрация документов
--
EXEC DL_Get_Documents N'6;1;7;20;12;13;5;22;17',N'#tDocuments',N'#flt'
--CREATE CLUSTERED INDEX ix_#tDocuments On #tDocuments (OwnerDistId, MasterFid, OrId)
--**************************************
--
--	непонятная временная таблица
--
SELECT
	f.Fid
	, obj.AttrText
	, vis.DateBegin
	, vis.DateEnd
	, vis.vDate
	, vis.vDateOnly
	, item.iID
INTO #temp
FROM #tFaces as f
LEFT JOIN DS_ObjectsAttributes AS obj
ON obj.AttrId=611
	AND obj.Id=f.Fid
	AND obj.DictId=2
LEFT JOIN #tVisits as vis
ON vis.Fid=f.Fid
LEFT JOIN DS_Items as item
ON item.iID=obj.Id
	AND ( item.iName LIKE '%Куш%'
		OR item.iName LIKE '%СКИТ%')
WHERE f.fType=7
ORDER BY vis.DateBegin

--
--	временная таблица, в которой находятся для залистиногованного
--
CREATE TABLE #it2
(
	AttrText NVARCHAR(255),	/*Наименование вывески*/
	iId INT,		/*ID товара*/
	sumSCIAndKush INT,	/*Число залаистиногованного товара*/
	orDate DATETIME
)

--
--	вставка первоначальных данных для подсчета процента присутствия
--
INSERT INTO #it2
SELECT
	DISTINCT t.AttrText
	, t.iID
	, 0
	, t.datebegin
FROM #temp AS t

UPDATE #it2
SET sumSCIAndKush = d.coun
FROM
( SELECT
		o.AttrText
		, item.iName
		, item.iID
		, COUNT(*) AS coun
	FROM DS_ObjectsAttributes AS o
	INNER JOIN DS_Items AS item
	ON item.iID=o.Id
		AND ( item.iName LIKE '%Куш%'
			OR item.iName LIKE '%СКИТ%')
	LEFT JOIN #temp as tmp
	ON tmp.AttrText=o.AttrText
	WHERE o.AttrId = 611
		AND o.AttrText IN (SELECT DISTINCT o1.AttrText FROM #temp AS o1)
		AND o.Activeflag=1
		AND o.DictId=1
	GROUP BY o.AttrText
		, item.iName
		, item.iID
) AS d
WHERE d.AttrText = #it2.AttrText
	AND d.iID=#it2.iId

--
--	данные по присутствующим товарам. Создание таблицы и первоначальная инициализация
--
CREATE TABLE #facing2
(
	mFid INT,
	sumSciAndKushFacing INT,	/*Атрибуты 695, 708, 694*/
	sumSCIAndKushPolk INT,	/*Атрибуты 634*/
	sumSCIAndKushSclad INT,	/*Атрибуты 635*/
	orComment NVARCHAR(250),
	DateBegin DATETIME,
    orId	INT,
    itId	INT		/*ID товара*/
)
/*
	первичная инициализация
*/
INSERT INTO #facing2
SELECT DISTINCT
	f.Fid AS mFid
	, 0
	, 0
	, 0
	, 0
	, vis.DateBegin
	, orid.OrId
	, orid.Id
FROM #tFaces AS f
LEFT JOIN #tVisits AS vis
ON f.Fid=vis.Fid
LEFT JOIN
(
	SELECT
		DISTINCT
			o.orId
			,o.mfID
			,o.OrDate
			, ord.Id
		FROM #tDocuments as o
		LEFT JOIN DS_Orders_Objects_Attributes as ord
		ON ord.AttrId in (695, 708, 694, 634, 635)
			AND ord.MasterFid=o.MasterFid
			AND ord.OrId=o.orId
			AND ord.OrObjAttrDate=o.OrDate
		INNER JOIN DS_Items AS it
		ON it.iID=ord.Id
		WHERE o.ortype=607
			AND(LEFT(it.iName ,3) LIKE '%СКИ%' OR LEFT(it.iName ,3) LIKE '%Куш%')
) AS orid
ON orid.mFid=f.Fid
WHERE f.fType=7

/*
	Подсчет числа Фэйсинга СКИТ и Кушать подано
*/
UPDATE #facing2
SET sumSciAndKushFacing = d.coun
FROM
( SELECT
		o.mFid
		, o.OrId
		, ord.Id
		, COUNT(*) AS coun
	FROM #tDocuments AS o
	LEFT JOIN DS_Orders_Objects_Attributes AS ord
	ON ord.AttrId in (695, 708, 694)
		AND ord.MasterFid=o.MasterFid
		AND ord.OrId=o.orId
		AND CAST(ord.OrObjAttrDate AS DATE)=CAST(o.OrDate AS DATE)
	INNER JOIN DS_Items as it
	ON it.iID=ord.Id
	WHERE o.ortype=607
		AND (LEFT(it.iName ,3) LIKE '%СКИ%' OR LEFT(it.iName ,3) LIKE '%Куш%')
	GROUP BY o.mFid, o.OrId, ord.Id
) AS d
WHERE d.mFid=#facing2.mFid
	AND d.Orid = #facing2.Orid
	AND d.Id = #facing2.itId

/*
	Подсчет Кол-во на полке СКИТ и КУШАТЬ ПОДАНО
*/
UPDATE #facing2
SET sumSCIAndKushPolk = d.coun
FROM
( SELECT
		o.mFid
		, o.OrId
		, ord.Id
		, COUNT(*) AS coun
	FROM #tDocuments AS o
	LEFT JOIN DS_Orders_Objects_Attributes AS ord
	ON ord.AttrId in (634)
		AND ord.MasterFid=o.MasterFid
		AND ord.OrId=o.orId
		AND CAST(ord.OrObjAttrDate AS DATE)=CAST(o.OrDate AS DATE)
	INNER JOIN DS_Items as it
	ON it.iID=ord.Id
	WHERE o.ortype=607
		AND (LEFT(it.iName ,3) LIKE '%СКИ%' OR LEFT(it.iName ,3) LIKE '%Куш%')
	GROUP BY o.mFid, o.OrId, ord.Id
) AS d
WHERE d.mFid=#facing2.mFid
	AND d.Orid = #facing2.Orid
	AND d.Id = #facing2.itId

/*
	Подсчет Кол-во на складе СКИТ и КУШАТЬ ПОДАНО
*/
UPDATE #facing2
SET #facing2.sumSCIAndKushSclad = d.coun
FROM
( SELECT
		o.mFid
		, o.OrId
		, ord.Id
		, COUNT(*) AS coun
	FROM #tDocuments AS o
	LEFT JOIN DS_Orders_Objects_Attributes AS ord
	ON ord.AttrId in (635)
		AND ord.MasterFid=o.MasterFid
		AND ord.OrId=o.orId
	INNER JOIN DS_Items as it
	ON it.iID=ord.Id
	WHERE o.ortype=607
		AND (LEFT(it.iName ,3) LIKE '%СКИ%' OR LEFT(it.iName ,3) LIKE '%Куш%')
	GROUP BY o.mFid, o.OrId, ord.Id
) AS d
WHERE d.mFid=#facing2.mFid
	AND d.Orid = #facing2.Orid
	AND d.Id = #facing2.itId

WITH tOrders(MasterFID, mfID, orID, orType, AttrId, orDate, AttrText, Id,  DictId) AS
(
	SELECT
		ord.MasterFID		/*ТП*/
		, ord.mfID			/*Клиент*/
		, ord.orID			/*ID заказа*/
		, ord.orType		/*Тип документа*/
		, ordobjtr.AttrId	/*Значение атрибута*/
		, ord.orDate		/*Дата Заказа*/
		, ordobjtr.AttrText
		, ordobjtr.Id		/*ID товара*/
		, ordobjtr.DictId
	FROM DS_Orders AS ord
	LEFT JOIN DS_Orders_Objects_Attributes AS ordobjtr
	ON ordobjtr.MasterFid = ord.MasterFID
		AND ordobjtr.OrId = ord.orID
		/*
			Фильтрация по выбранным параметрам отчета (МАСТЕРФИДУ)
		*/
		AND ord.MasterFID IN (	SELECT vis.MasterFid
								FROM #tVisits AS vis
								GROUP BY vis.MasterFid)
		/*
			Фильтрация по выбранным параметрам отчета (ФИДУ)
		*/
		AND ord.mfID IN (	SELECT vis.Fid
							FROM #tVisits AS vis
							GROUP BY vis.Fid)
	WHERE ord.orDate BETWEEN @bDate AND @edate
		/*
			Фильтрация по необходимым документам
		*/
		AND ord.orType IN (613, 610, 608, 612, 611)
		/*
			Проверка на активность
		*/
		AND ordobjtr.ActiveFlag =1
)

SELECT
	/*613-ый документ*/
	N'613ый документ=>'
	, (SELECT it.iName FROM DS_ITEMS AS it WHERE it.iID = ord613_items.Id) AS [Наименование]	/*Наименование ассортимента*/
	, ISNULL(ord613_620atr.AttrText, 0) AS [Фейсинг] /*Фейсинг. 620ый атрибут*/
	, ISNULL(ord613_634atr.AttrText, 0) AS [Кол-во на полке]/*Кол-во на полке (шт). 634ый атрибут*/
	, ISNULL(ord613_635atr.AttrText, 0) AS [Кол-во на складе]/*Кол-во на складе (шт)	635ый атрибут*/
	, ISNULL(CAST(ord613_620atr.AttrText AS FLOAT), 0) + ISNULL(CAST(ord613_634atr.AttrText AS FLOAT), 0) + ISNULL(CAST(ord613_635atr.AttrText AS FLOAT), 0) AS [ИТОГО]
	, N'ПУСТО' AS [Out of Stock]
	, N'ПУСТО' AS [Залистингованно]
	, N'ПУСТО' AS [% присутствия]
	, N'<=613ый документ'
	/*613-ый документ*/
	/*610-ый документ*/
	, N'610ый документ=>'
	, ord610_602atr.AttrText
	, N'<=610ый документ'
	/*610-ый документ*/
	/*608-ой документ*/
	, N'608-ой документ=>'
	, ord608.Attr1000005 AS [полка]
	, ord608.Attr1000006 AS [каноэ]
	, ord608.Attr1000007 AS [паллета]
	, ord608.Attr1000008 AS [хол. витрина]
	, ord608.Attr1000009 AS [холодильник]
	, ord608.Attr1000010 AS [корзина]
	, N'<=608-ой документ'
	/*608-ой документ*/
	/*612-ый документ*/
	, N'612-ый документ=>'
	, (SELECT it.iName FROM DS_ITEMS AS it WHERE it.iID = ord612_items.Id) AS [Наименование]	/*Наименование ассортимента*/
	, ord612.Attr612 AS [Стойки]
	, ord612.Attr613 AS [Торец гондолы]
	, ord612.Attr614 AS [Паллета]
	, ord612.Attr615 AS [Другое]
	, ord612.Attr616 AS [Нет доп.места]
	, N'<=612-ый документ'
	/*612-ый документ*/
	/*611-ый документ*/
	, N'611-ый документ=>'
	, (SELECT it.iName FROM DS_ITEMS AS it WHERE it.iID = ord611_items.Id) AS [Наименование]	/*Наименование ассортимента*/
	, REPLACE(ord611.Attr603, '.', ',') AS [снижение цены]
	, ord611.Attr604 AS [2+1]
	, ord611.Attr605 AS [1+1]
	, ord611.Attr606 AS [примотка]
	, N'<=611-ый документ'
	/*611-ый документ*/
	, vis.MasterFid
	, vis.Fid
FROM #tVisits AS vis
/*
	Присоединение OrID + MasterFid по 613 ому документу
	Необходимо для "СКИТ Кушать подано":
		а)	Наименов. ассортим.
		б)	Фейсинг(фронт полки, шт)
		в)	Кол-во на полке (шт)	634ый атрибут
		г)	Кол-во на складе (шт)	635ый атрибут
		д)	Итого кол-во шт (авто)	сумма б, в, г, д
		е)	Out-of-stock /*пока нет данных*/
		ж)	Залистовано SKU (авто)
		з)	% присутствия
*/
/*
	Присоединение различного ассортимента по ID
	По полученному ID будем присоединять группы товаров
	По заданному типу документов
	Сейчас тип документа = 613
*/
INNER JOIN
(
	SELECT	ord613.MasterFID
			, ord613.mfID
			, ord613.Id
	FROM tOrders AS ord613
	WHERE ord613.orType = 613
	GROUP BY ord613.MasterFID
			, ord613.mfID
			, ord613.Id
) AS ord613_items
ON	ord613_items.MasterFID = vis.MasterFid
	AND ord613_items.mfID = vis.Fid
/*
	Присоединение "Фэйсинг"
	Ключ: МАСТЕРФИД + ФИД + id ТОВАРА
*/
LEFT JOIN
(
	SELECT ord613.MasterFID
			, ord613.mfID
			, ord613.AttrText
			, ord613.Id
			, ord613.orDate
	FROM tOrders AS ord613
	WHERE ord613.orType = 613
		AND ord613.AttrId = 620
) AS ord613_620atr
ON	ord613_620atr.MasterFid = vis.MasterFid
	AND ord613_620atr.mfID = vis.Fid
	AND ord613_620atr.Id = ord613_items.Id
/*
	Присоединение "Кол-во на полке"
	Ключ: МАСТЕРФИД + ФИД + id ТОВАРА
*/
LEFT JOIN
(
	SELECT ord613.MasterFID
			, ord613.mfID
			, ord613.AttrText
			, ord613.Id
			, ord613.orDate
	FROM tOrders AS ord613
	WHERE ord613.orType = 613
		AND ord613.AttrId = 634
) AS ord613_634atr
ON	ord613_634atr.MasterFid = vis.MasterFid
	AND ord613_634atr.mfID = vis.Fid
	AND ord613_items.Id = ord613_634atr.Id
/*
	Присоединение "Кол-во на складе (шт)"
	Ключ: МАСТЕРФИД + ФИД + id ТОВАРА
*/
LEFT JOIN
(
	SELECT ord613.MasterFID
			, ord613.mfID
			, ord613.AttrText
			, ord613.Id
			, ord613.orDate
	FROM tOrders AS ord613
	WHERE ord613.orType = 613
		AND ord613.AttrId = 635
) AS ord613_635atr
ON	ord613_635atr.MasterFid = vis.MasterFid
	AND ord613_635atr.mfID = vis.Fid
	AND ord613_635atr.Id = ord613_items.Id
/*
	610-ый документ
*/
LEFT JOIN
(
	/*
		информация о заказе. Берется из 610ого документа
		присоединяем данные по информации по заказу к  по orID и MasterFid
	*/
	SELECT ord610.MasterFID
			, ord610.mfID
			, ord610.AttrText
	FROM	tOrders AS ord610
	INNER JOIN	#tDocuments AS tdoc610
	/*
		Ключ по мастерфид + фид + оrId
	*/
	ON tdoc610.MasterFid = ord610.MasterFID
		AND tdoc610.mFid = ord610.mfID
		AND tdoc610.OrId = ord610.orID
		/*
			проверка на то, что мы смотрим последний документа по этой точке
		*/
		AND tdoc610.OrDate = (SELECT MAX(docb.OrDate)
							FROM #tDocuments AS docb
							WHERE docb.MasterFid = tdoc610.MasterFid
								AND docb.mFid=tdoc610.mFid
								AND docb.OrType = 610
							GROUP BY docb.MasterFid, docb.mFid)
		/*
			Оставляем только информацию о заказе
		*/
		AND ord610.AttrId = 602

) AS ord610_602atr
ON ord610_602atr.MasterFid = vis.MasterFid
	AND ord610_602atr.mFid = vis.Fid
/*
	Присоединение 608-ого документа
	Присоединение связки MasterFid + OrId по 608 документу
	Необходимо для "Основные места продаж":
		а)	Полка
		б)	Каноэ
		в)	Паллета
		г)	Холодильная  витрина
		д)	Холодильник
		е)	Корзина
*/
LEFT JOIN
(
	/*
		информация о заказе. Берется из 608ого документа
		присоединяем данные по информации по заказу к  по orID и MasterFid
	*/
	SELECT ord608.MasterFID
			, ord608.mfID
			, ord608.orID
			, ord608.Id
			/*
				Старый механизм
			*/
			, MAX( CASE WHEN ord608.Id  = 1000005 THEN ord608.AttrText ELSE N'' END ) AS Attr1000005
			, MAX( CASE WHEN ord608.Id  = 1000006 THEN ord608.AttrText ELSE N'' END ) AS Attr1000006
			, MAX( CASE WHEN ord608.Id  = 1000007 THEN ord608.AttrText ELSE N'' END ) AS Attr1000007
			, MAX( CASE WHEN ord608.Id  = 1000008 THEN ord608.AttrText ELSE N'' END ) AS Attr1000008
			, MAX( CASE WHEN ord608.Id  = 1000009 THEN ord608.AttrText ELSE N'' END ) AS Attr1000009
			, MAX( CASE WHEN ord608.Id  = 1000010 THEN ord608.AttrText ELSE N'' END ) AS Attr1000010
	FROM	tOrders AS ord608
	INNER JOIN	#tDocuments AS tdoc608
	/*
		Ключ по мастерфид + фид + оrId
	*/
	ON tdoc608.MasterFid = ord608.MasterFID
		AND tdoc608.mFid = ord608.mfID
		AND tdoc608.OrId = ord608.orID
		/*
			проверка на то, что мы смотрим последний документа по этой точке
		*/
		AND tdoc608.OrDate = (SELECT MAX(docb.OrDate)
							FROM #tDocuments AS docb
							WHERE docb.MasterFid = tdoc608.MasterFid
								AND docb.mFid=tdoc608.mFid
								AND docb.OrType = 608
							GROUP BY docb.MasterFid, docb.mFid)
		AND ord608.Id IN (1000005, 1000006, 1000007, 1000008, 1000009, 1000010)
		/*
			Фильтрация по типу документа
		*/
		AND tdoc608.OrType = 608
		AND ord608.DictId = 1
	GROUP BY ord608.orID
			, ord608.MasterFID
			, ord608.mfID
			, ord608.Id
) AS ord608
ON ord608.MasterFid = vis.MasterFid
	AND ord608.mFid = vis.Fid
	AND ord608.Id = ord613_items.Id
/*
	612ый документ
*/
/*
	Присоединение различного ассортимента по ID
	По полученному ID будем присоединять группы товаров
	По заданному типу документов
	Сейчас тип документа = 612
*/
INNER JOIN
(
	SELECT	ord612.MasterFID
			, ord612.mfID
			, ord612.Id
	FROM tOrders AS ord612
	WHERE ord612.orType = 612
	GROUP BY ord612.MasterFID
			, ord612.mfID
			, ord612.Id
) AS ord612_items
ON	ord612_items.MasterFID = vis.MasterFid
	AND ord612_items.mfID = vis.Fid
/*
	Информация по последему orId документа 612
		*Стойки, торец гондолы]
		*паллета
		*другое
		*нет доп. места
*/
LEFT JOIN
(
	SELECT ord612.MasterFID
			, ord612.mfID
			, ord612.orID
			, ord612.Id
			/*
				Старый механизм
			*/
			, MAX( CASE WHEN ord612.AttrId  = 615 THEN ord612.AttrText ELSE N'' END ) AS Attr615
			, MAX( CASE WHEN ord612.AttrId  = 614 THEN ord612.AttrText ELSE N'' END ) AS Attr614
			, MAX( CASE WHEN ord612.AttrId  = 612 THEN ord612.AttrText ELSE N'' END ) AS Attr612
			, MAX( CASE WHEN ord612.AttrId  = 613 THEN ord612.AttrText ELSE N'' END ) AS Attr613
			, MAX( CASE WHEN ord612.AttrId  = 616 THEN ord612.AttrText ELSE N'' END ) AS Attr616
	FROM	tOrders AS ord612
	INNER JOIN	#tDocuments AS tdoc612
	/*
		Ключ по мастерфид + фид + оrId
	*/
	ON tdoc612.MasterFid = ord612.MasterFID
		AND tdoc612.mFid = ord612.mfID
		AND tdoc612.OrId = ord612.orID
		/*
			проверка на то, что мы смотрим последний документа по этой точке
		*/
		AND tdoc612.OrDate = (SELECT MAX(docb.OrDate)
							FROM #tDocuments AS docb
							WHERE docb.MasterFid = tdoc612.MasterFid
								AND docb.mFid=tdoc612.mFid
								AND docb.OrType = 612
							GROUP BY docb.MasterFid, docb.mFid)
		AND ord612.Id IN (615, 614, 612, 613, 616)
		/*
			Фильтрация по типу документа
		*/
		AND tdoc612.OrType = 612
		AND ord612.DictId = 1
	GROUP BY ord612.orID
			, ord612.MasterFID
			, ord612.mfID
			, ord612.Id
) AS ord612
ON	ord612.MasterFid = vis.MasterFid
	AND ord612.mFid = vis.Fid
	AND ord612.Id = ord612_items.Id
/*
	Информация по 611 ому документу
*/
/*
	Присоединение различного ассортимента по ID
	По полученному ID будем присоединять группы товаров
	По заданному типу документов
	Сейчас тип документа = 611
*/
INNER JOIN
(
	SELECT	ord611.MasterFID
			, ord611.mfID
			, ord611.Id
	FROM tOrders AS ord611
	WHERE ord611.orType = 611
	GROUP BY ord611.MasterFID
			, ord611.mfID
			, ord611.Id
) AS ord611_items
ON	ord611_items.MasterFID = vis.MasterFid
	AND ord611_items.mfID = vis.Fid
/*
	Присоединение информации по 611 ому документу
*/
LEFT JOIN
(
	SELECT ord611.MasterFID
			, ord611.mfID
			, ord611.orID
			, ord611.Id
			/*
				Старый механизм
			*/
			, MAX( CASE WHEN ord611.AttrId  = 603 THEN ord611.AttrText ELSE N'' END ) AS Attr603	/*Снижение цены*/
			, MAX( CASE WHEN ord611.AttrId  = 604 THEN ord611.AttrText ELSE N'' END ) AS Attr604	/*2+1*/
			, MAX( CASE WHEN ord611.AttrId  = 605 THEN ord611.AttrText ELSE N'' END ) AS Attr605	/*1+1*/
			, MAX( CASE WHEN ord611.AttrId  = 606 THEN ord611.AttrText ELSE N'' END ) AS Attr606	/*Примотка*/
	FROM	tOrders AS ord611
	INNER JOIN	#tDocuments AS tdoc611
	/*
		Ключ по мастерфид + фид + оrId
	*/
	ON tdoc611.MasterFid = ord611.MasterFID
		AND tdoc611.mFid = ord611.mfID
		AND tdoc611.OrId = ord611.orID
		/*
			проверка на то, что мы смотрим последний документа по этой точке
		*/
		AND tdoc611.OrDate = (SELECT MAX(docb.OrDate)
							FROM #tDocuments AS docb
							WHERE docb.MasterFid = tdoc611.MasterFid
								AND docb.mFid=tdoc611.mFid
								AND docb.OrType = 611
							GROUP BY docb.MasterFid, docb.mFid)
		AND ord611.Id IN (603, 604, 605, 606)
		/*
			Фильтрация по типу документа
		*/
		AND tdoc611.OrType = 611
	GROUP BY ord611.orID
			, ord611.MasterFID
			, ord611.mfID
			, ord611.Id
) AS ord611
ON	ord611.MasterFid = vis.MasterFid
	AND ord611.mFid = vis.Fid
	AND ord611.Id = ord611_items.Id

--select * from #tDocuments
/*
/*
	ФИНАЛЬНЫЙ ЗАПРОС
*/
SELECT
	faces.fName AS [Сотрудник СКИТ]
	, vis.DateBegin AS [Дата аудита]
	, faces.nomerTT AS [№ ТТ]
	, '' AS [Категория магазина]
	, atr611.AttrText AS [Сеть / Название ТТ]
	, faces.gorod AS [Город]
	, N'' AS [Район]
	, faces.street AS [Улица] /*найдено*/
	, faces.dom AS [Дом] /*найдено*/
	, vis.OtkazStr AS [Магазин закрыт] /*найдено*/
	/*	607ой документ!*/

	, item607.iName
	, CASE
		WHEN facing607.sumSciAndKushFacing=0 THEN N''
		ELSE CAST(facing607.sumSciAndKushFacing AS NVARCHAR)
	  END  AS [Фэйсинг]
	 , CASE
		WHEN facing607.sumSCIAndKushPolk=0 THEN N''
		ELSE CAST(facing607.sumSCIAndKushPolk AS NVARCHAR)
	  END  AS [Кол-во на полке]
	  , CASE
		WHEN facing607.sumSCIAndKushSclad=0 THEN N''
		ELSE CAST(facing607.sumSCIAndKushSclad AS NVARCHAR)
	  END  AS [Кол-во на складе]
	, CASE
		WHEN listing607.sumSCIAndKush=0 THEN N''
		ELSE CAST(listing607.sumSCIAndKush AS NVARCHAR)
	  END AS [Залистингованных]
	 , ISNULL(facing607.sumSciAndKushFacing,0) + ISNULL(facing607.sumSCIAndKushPolk, 0) + ISNULL(facing607.sumSCIAndKushSclad, 0) + ISNULL(listing607.sumSCIAndKush, 0) AS [Итого]
	/*607ой */
	/*610ый документ*/
	, dssoa610.AttrText AS [Информация о заказе]
	/*610ый документ*/
	/*608ой документ*/
	, tdoc608data.Attr1000005 AS [полка]
	, tdoc608data.Attr1000006 AS [каноэ]
	, tdoc608data.Attr1000007 AS [паллета]
	, tdoc608data.Attr1000008 AS [хол. витрина]
	, tdoc608data.Attr1000009 AS [холодильник]
	, tdoc608data.Attr1000010 AS [корзина]
	/*608ой документ*/
	/*612ый документ*/
	, items612.iName AS [Наименование из ассортимента]
	, tdoc612data.Attr612 AS [Стойки]
	, tdoc612data.Attr613 AS [торец гондолы]
	, tdoc612data.Attr614 AS [паллета]
	, tdoc612data.Attr615 AS [другое]
	, tdoc612data.Attr616 AS [нет доп. места]
	/*612ый документ*/
	/*611ый документ*/
	, items611.iName AS [ Наименование из ассортимента]
	, REPLACE(tdoc611data.Attr603, '.', ',') AS [снижение цены]
	, tdoc611data.Attr604 AS [2+1]
	, tdoc611data.Attr605 AS [1+1]
	, tdoc611data.Attr606 AS [примотка]
	/*611ый документ*/

	, CASE
		WHEN listing607.sumSCIAndKush<>0 AND facing607.sumSciAndKushFacing<>0 THEN CAST(CAST(CAST(facing607.sumSciAndKushFacing AS DECIMAL(2,1))/listing607.sumSCIAndKush*100 AS INT) AS NVARCHAR)
		WHEN listing607.sumSCIAndKush=0 OR facing607.sumSciAndKushFacing=0 THEN N''
	  END AS [% присутстивия СКИТ] /*просто подсчет процентов*/

	, fac.fName AS [Супервайзер СКИТ]
	, facing607.orComment AS [Комментарий фейсинг]
	, mpv.Comment AS [комментарий по визиту]
	, CAST(doc5.MasterFid AS NVARCHAR)+cast(dateDoc5.OrId AS NVARCHAR) AS [Фотография] /* найдено*/
	, '' AS [Фотография 2]
	, '' AS [Фотография 3]

	, atr.AttrText as [почта] /*найдено*/
FROM #tVisits as vis
/*
	Присоединение OrID + MasterFid по 607 ому документу
	Необходимо для "СКИТ Кушать подано":
		а)	Наименов. ассортим.
		б)	Фейсинг(фронт полки, шт)
		в)	Кол-во на полке (шт)
		г)	Кол-во на складе (шт)
		д)	Итого кол-во шт (авто)
		е)	Out-of-stock /*пока нет данных*/
		ж)	Залистовано SKU (авто)
		з)	% присутствия
*/
LEFT JOIN
(
	SELECT	dso607.orID AS [orID607]
			,dso607.MasterFID
			,dso607.mfID
			,dso607.orDate AS [orDate607]
	FROM DS_Orders AS dso607
	WHERE dso607.orType = 607
		AND YEAR(@bDate) = YEAR(dso607.orDate)
		AND MONTH(@bDate) = MONTH(dso607.orDate)
		AND DAY(@bDate) = DAY(dso607.orDate)
)  AS ord607
ON vis.MasterFid = ord607.MasterFID
	AND vis.Fid = ord607.mfID

/*
	вывеска предприятия
*/
LEFT JOIN DS_ObjectsAttributes AS atr611
ON atr611.Id=vis.Fid
	AND atr611.AttrId=611
	AND atr611.DictId=2
/*
	Присоединение фейсинг
*/
LEFT JOIN #facing2 AS facing607
ON facing607.mFid=vis.Fid
	AND facing607.DateBegin=vis.DateBegin
/*
	Присоединение наименования
*/
LEFT JOIN DS_Items AS item607
ON facing607.itId = item607.iID
/*
	Для каждой вывески предприятия считается своё залистингованное значение
*/
LEFT JOIN #it2 AS listing607
ON listing607.AttrText=atr611.AttrText
	AND listing607.orDate=vis.Datebegin
	AND listing607.iId = facing607.itId

/**================================	612-ый документ==============================*/
/*
	Присоединение связки MasterFid + OrId по 612 документу
	Необходимо для "Дополнительные места продаж майонезов"
		а)	Наименов. ассортим.
		б)	Стойки
		в)	Торец гондолы
		г)	Паллета
		д)	Другое
*/
LEFT JOIN
(
	SELECT	dso612.orID AS [orID612]
			,dso612.MasterFID
			,dso612.mfID
			,dso612.orDate AS [orDate612]
	FROM DS_Orders AS dso612
	WHERE dso612.orType=612
		AND YEAR(@bDate) = YEAR(dso612.orDate)
		AND MONTH(@bDate) = MONTH(dso612.orDate)
		AND DAY(@bDate) = DAY(dso612.orDate)
)  AS ord612
ON vis.MasterFid=ord612.MasterFID
	AND vis.Fid=ord612.mfID
	/*
		ЗАЧЕМ??!
	*/
	AND ord612.orID612-ord607.orID607=1
/*
	Находим последний документ типа 612
	За выбранную дату по рассматриваемым MasterFid и Fid.
*/
LEFT JOIN
(
	SELECT	tdoc612.MasterFid,
		tdoc612.mFid,
		tdoc612.OrId
	FROM #tDocuments AS tdoc612
	WHERE tdoc612.OrType = 612
		/*
			поиск записи с максимальной датой по данной связке
			MasterFid и mFid
		*/
		AND tdoc612.OrDate = (SELECT MAX(docb.OrDate)
							FROM #tDocuments AS docb
							WHERE docb.MasterFid = tdoc612.MasterFid
								AND docb.mFid = tdoc612.mFid
								AND docb.OrType = 612
							GROUP BY docb.MasterFid, docb.mFid)
) AS tdoc612
ON tdoc612.MasterFid = ord612.MasterFID
	AND tdoc612.mFid = ord612.mfID
	AND tdoc612.OrId = ord612.orID612
/*
	Информация по последему orId документа 612
		*Стойки, торец гондолы]
		*паллета
		*другое
		*нет доп. места
*/
LEFT JOIN
(
	SELECT
		obj.OrId
		, obj.Id
		, obj.MasterFid
		, MAX( CASE WHEN obj.Attrid  = 615 THEN obj.AttrText ELSE N'' END ) AS Attr615
		, MAX( CASE WHEN obj.Attrid  = 614 THEN obj.AttrText ELSE N'' END ) AS Attr614
		, MAX( CASE WHEN obj.Attrid  = 612 THEN obj.AttrText ELSE N'' END ) AS Attr612
		, MAX( CASE WHEN obj.Attrid  = 613 THEN obj.AttrText ELSE N'' END ) AS Attr613
		, MAX( CASE WHEN obj.Attrid  = 616 THEN obj.AttrText ELSE N'' END ) AS Attr616
	FROM DS_Orders_Objects_Attributes AS obj
	INNER JOIN #tDocuments AS doc
	ON doc.OrId=obj.OrId
	    AND doc.MasterFid=obj.MasterFid
		AND	obj.AttrId in (615, 614, 612, 613, 616)
		AND obj.Activeflag=1
		AND obj.DictId=1
		AND doc.OrType=612
	GROUP BY obj.OrId, obj.Id, obj.MasterFid
) AS tdoc612data
ON tdoc612data.OrId=tdoc612.OrId
	and tdoc612data.MasterFid=tdoc612.MasterFid
--
--	наименование товара
--
LEFT JOIN DS_ITEMS AS items612
ON items612.iID=tdoc612data.Id
/**================================	612-ый документ==============================*/
/**================================	608-ой документ==============================*/
/*
	Присоединение связки MasterFid + OrId по 608 документу
	Необходимо для "Основные места продаж":
		а)	Полка
		б)	Каноэ
		в)	Паллета
		г)	Холодильная  витрина
		д)	Холодильник
		е)	Корзина
*/
LEFT JOIN
(
	SELECT	dso608.orID AS [orID608]
			,dso608.MasterFID
			,dso608.mfID
			,dso608.orDate
	FROM DS_Orders as dso608
	WHERE dso608.orType = 608
		AND YEAR(@bDate) = YEAR(dso608.orDate)
		AND MONTH(@bDate) = MONTH(dso608.orDate)
		AND DAY(@bDate) = DAY(dso608.orDate)
)  AS ord608
ON  vis.MasterFid=ord608.MasterFID
	AND vis.Fid=ord608.mfID
	/*
		ЗАЧЕМ??!
	*/
	AND ord608.orID608-ord612.orID612=1
/*
	Находим последний документ типа 608
	За выбранную дату по рассматриваемым MasterFid и Fid.
*/
LEFT JOIN
(
	SELECT	tdoc608.MasterFid,
		tdoc608.mFid,
		tdoc608.OrId
	FROM #tDocuments AS tdoc608
	WHERE tdoc608.OrType = 608
		/*
			поиск записи с максимальной датой по данной связке
			MasterFid и mFid
		*/
		AND tdoc608.OrDate = (SELECT MAX(docb.OrDate)
							FROM #tDocuments AS docb
							WHERE docb.MasterFid = tdoc608.MasterFid
								AND docb.mFid = tdoc608.mFid
								AND docb.OrType = 608
							GROUP BY docb.MasterFid, docb.mFid)
) AS tdoc608
ON tdoc608.MasterFid = ord608.MasterFID
	AND tdoc608.mFid = ord608.mfID
	AND tdoc608.OrId = ord608.orID608
/*
	Информация по последему orId документа 608
		*полка
		*каноэ
		*паллета
		*хол. витрина
		*холодильник
		*корзина
*/
LEFT JOIN
(
	SELECT
		obj.OrId
		, obj.MasterFid
		, obj.Id
		, MAX( CASE WHEN obj.Id  = 1000005 THEN obj.AttrText ELSE N'' END ) AS Attr1000005
		, MAX( CASE WHEN obj.Id  = 1000006 THEN obj.AttrText ELSE N'' END ) AS Attr1000006
		, MAX( CASE WHEN obj.Id  = 1000007 THEN obj.AttrText ELSE N'' END ) AS Attr1000007
		, MAX( CASE WHEN obj.Id  = 1000008 THEN obj.AttrText ELSE N'' END ) AS Attr1000008
		, MAX( CASE WHEN obj.Id  = 1000009 THEN obj.AttrText ELSE N'' END ) AS Attr1000009
		, MAX( CASE WHEN obj.Id  = 1000010 THEN obj.AttrText ELSE N'' END ) AS Attr1000010
	FROM DS_Orders_Objects_Attributes AS obj
	INNER JOIN #tDocuments AS doc
	ON doc.OrId=obj.OrId
	    AND doc.MasterFid=obj.MasterFid
		AND	obj.Id IN (1000005, 1000006, 1000007, 1000008, 1000009, 1000010)
		AND obj.Activeflag=1
		AND doc.OrType=608
		AND obj.DictId=1
	GROUP BY obj.OrId, obj.MasterFid, obj.Id
) AS tdoc608data
ON tdoc608data.OrId = tdoc608.OrId
	AND tdoc608data.MasterFid = tdoc608.MasterFid
	AND tdoc608data.id = facing607.itId
/**================================	608-ой документ==============================*/
/**================================	611-ый документ==============================*/
/*
	Присоединение связки MasterFid + OrId по 611 документу
	Необходимо для "Трейд-маркетинговые мероприятия":
		а)	Наименов. ассортим.
		б)	Снижение цены
		в)	2+1
		г)	1+1
		д)	Примотка
*/
LEFT JOIN
(
	SELECT	dso611.orID AS [orID611]
			,dso611.MasterFID
			,dso611.mfID
			,dso611.orDate
	FROM DS_Orders AS dso611
	WHERE dso611.orType = 611
		AND YEAR(@bDate) = YEAR(dso611.orDate)
		AND MONTH(@bDate) = MONTH(dso611.orDate)
		AND DAY(@bDate) = DAY(dso611.orDate)
)  AS ord611
ON vis.MasterFid=ord611.MasterFID
	AND vis.Fid=ord611.mfID
	/*
		ЗАЧЕМ??!
	*/
	AND ord611.orID611-ord607.orID607 BETWEEN 1 AND 4
/*
	Находим последний документ типа 611
	За выбранную дату по рассматриваемым MasterFid и Fid.
*/
LEFT JOIN
(
	SELECT	tdoc611.MasterFid,
		tdoc611.mFid,
		tdoc611.OrId
	FROM #tDocuments AS tdoc611
	WHERE tdoc611.OrType = 611
		/*
			поиск записи с максимальной датой по данной связке
			MasterFid и mFid
		*/
		AND tdoc611.OrDate = (SELECT MAX(docb.OrDate)
							FROM #tDocuments AS docb
							WHERE docb.MasterFid = tdoc611.MasterFid
								AND docb.mFid = tdoc611.mFid
								AND docb.OrType = 611
							GROUP BY docb.MasterFid, docb.mFid)
) AS tdoc611
ON tdoc611.MasterFid = ord611.MasterFID
	AND tdoc611.mFid = ord611.mfID
	AND tdoc611.OrId = ord611.orID611
/*
	Информация по последему orId документа 608
		*снижение цены
		*2+1
		*1+1
		*примотка
 */
LEFT JOIN
(
	SELECT
		obj.OrId
		, obj.Id
		, obj.MasterFid
		, MAX( CASE WHEN obj.AttrId  = 603 THEN obj.AttrText ELSE N'' End ) AS Attr603	/*Снижение цены*/
		, MAX( CASE WHEN obj.AttrId  = 604 THEN obj.AttrText ELSE N'' End ) AS Attr604	/*2+1*/
		, MAX( CASE WHEN obj.AttrId  = 605 THEN obj.AttrText ELSE N'' End ) AS Attr605	/*1+1*/
		, MAX( CASE WHEN obj.AttrId  = 606 THEN obj.AttrText ELSE N'' End ) AS Attr606	/*Примотка*/
	FROM DS_Orders_Objects_Attributes AS obj
	INNER JOIN #tDocuments AS doc
	ON doc.MasterFid=obj.MasterFid
		AND	obj.AttrId IN (603, 604, 605, 606)
		AND obj.Activeflag = 1
		AND doc.OrType = 611
	GROUP BY obj.OrId, obj.Id, obj.MasterFid
) AS tdoc611data
ON tdoc611data.OrId=tdoc611.OrId
	AND tdoc611data.MasterFid=tdoc611.MasterFid
/*
	Присоединение наименования
*/
LEFT JOIN DS_Items AS items611
ON items611.iID=tdoc611data.Id
/**================================	611-ый документ==============================*/
/**================================	610-ый документ==============================*/
/*
	Присоединение связки MasterFid + OrId по 610 документу
	Необходимо для "Информация о заказе"
*/
LEFT JOIN
(
	SELECT	dso610.orID as [orID610]
			, dso610.MasterFID
			, dso610.mfID
			, dso610.orDate
	FROM DS_Orders as dso610
	WHERE dso610.orType = 610
		AND YEAR(@bDate) = YEAR(dso610.orDate)
		AND MONTH(@bDate) = MONTH(dso610.orDate)
		AND DAY(@bDate) = DAY(dso610.orDate)
)  AS dso610
ON vis.MasterFid = dso610.MasterFID
	AND vis.Fid = dso610.mfID
	/*
		ЗАЧЕМ??
	*/
	AND dso610.orID610-ord607.orID607 BETWEEN 1 AND 7
/*
	Находим последний документ типа 610
	За выбранную дату по рассматриваемым MasterFid и Fid.
*/
LEFT JOIN
(
	SELECT	tdoc610.MasterFid,
		tdoc610.mFid,
		tdoc610.OrId
	FROM #tDocuments AS tdoc610
	WHERE tdoc610.OrType = 610
		/*
			поиск записи с максимальной датой по данной связке
			MasterFid и mFid
		*/
		AND tdoc610.OrDate = (SELECT MAX(docb.OrDate)
							FROM #tDocuments AS docb
							WHERE docb.MasterFid = tdoc610.MasterFid
								AND docb.mFid=tdoc610.mFid
								AND docb.OrType = 610
							GROUP BY docb.MasterFid, docb.mFid)
) AS tdoc610
ON tdoc610.MasterFid = vis.MasterFid
	AND tdoc610.mFid = vis.Fid
	AND tdoc610.OrId = dso610.orID610
/*
	информация о заказе. Берется из 610ого документа
	присоединяем данные по информации по заказу к по orID и MasterFid
*/
LEFT JOIN DS_Orders_Objects_Attributes AS dssoa610
ON dssoa610.OrId=tdoc610.OrId
	AND dssoa610.MasterFid=tdoc610.MasterFid
	AND dssoa610.AttrId=602
/**================================	610-ый документ==============================*/
/*
	Данные по Сотруднику СКИТ
*/
LEFT JOIN #tFaces AS faces
ON faces.Fid=vis.Fid

--
--	Супервайзер СКИТ
--
LEFT JOIN #tFaces AS fac
ON fac.Fid=vis.MasterFid
--
--	комментарий по визиту
--
left join
	DS_merPointsVisits as mpv
	on mpv.fID=vis.Fid
	and mpv.vDate=vis.vDate
--
--	OrId для фотографий
--
LEFT JOIN
(
	SELECT
		doc.MasterFid,
		doc.mFid,
		MAX(doc.OrDate) AS orDate
		,DOC.OrId
	FROM #tDocuments as doc
	WHERE doc.OrType=230
		AND CAST(doc.OrDate AS DATE) BETWEEN @bDate AND @eDate
	GROUP BY doc.MasterFid, doc.mFid ,doc.OrId
) AS dateDoc5
ON dateDoc5.MasterFid=vis.MasterFid
	AND dateDoc5.mFid=vis.Fid
	AND facing607.orId - dateDoc5.OrId IN (-1,1)
--
--	для фотографий
--
LEFT JOIN #tDocuments AS doc5
ON doc5.MasterFid=dateDoc5.MasterFid
	AND doc5.mFid=dateDoc5.mFid
	AND doc5.OrDate=dateDoc5.orDate
	AND doc5.OrId = datedoc5.orId
	AND doc5.OrType=230
--
--	почта
--
LEFT JOIN
(
	SELECT
		atr.Id
		,atr.AttrText
	FROM DS_ObjectsAttributes AS atr
	WHERE atr.AttrId in (633)
		and atr.Activeflag=1
) AS atr
ON atr.Id=vis.fId
ORDER BY fac.fName,vis.DateBegin,facing607.orId

if  exists
	(
		select top 1 1
		from #tDocuments
	)
begin
	Declare @tcmd nvarchar(4000)
	, @BaseDir nvarchar(256)
	set @BaseDir=N'C:\inetpub\wwwroot\WarmSetup\App_Data\Report\WarmSetup'
	If SubString ( @BaseDir , Len ( @BaseDir ) , 1 ) <> '\'
	Set @BaseDir = @BaseDir + '\'
	Declare @cmd nvarchar ( 4000 )
	Set @tcmd = 'mkdir ' + '"'+ @BaseDir + '"'
	--print '@tcmd1=' + @tcmd
	exec master.dbo.xp_cmdshell @tcmd, no_output

	Set @cmd = 'Echo 8.0 >"'+@BaseDir+'tscript.fmt"'
	--print '@cmd2=' + @cmd
	EXEC master..xp_cmdshell @cmd, no_output

	Set @cmd = 'Echo 1 >>"'+@BaseDir+'tscript.fmt"'
	--print '@cmd3=' + @cmd
	EXEC master..xp_cmdshell @cmd, no_output

	Set @cmd = 'Echo 1       SQLBINARY	0       0    ""   1     FaceImage	""  >>"'+@BaseDir+'tscript.fmt"'
	--print '@cmd4=' + @cmd
	EXEC master..xp_cmdshell @cmd, no_output
	Declare @FileName nvarchar(30)
	Declare @num int
	Declare @exi nvarchar(4)
	set @exi=N'.jpg'
	set @num=0

--*****************************************
create table #t2 (Mas int,OrID int,orType int,FileID int)
insert into #t2
select 	t.MasterFid
     , t.OrId
     , t.orType
     , at.FileID
     --,COUNT(*) as [Сумма11]
     --,t.orId
 from #tDocuments as t
 left join
  DS_DocAttachments as at
  on at.MasterFID=t.MasterFid
  and at.DocID=t.OrId

 create table #t3 (MasterFid int,OrID int,orType int,FileID int,rnk int)
 insert into #t3
 select * ,( select count(*) from #t2  As t2
where t2.OrID=#t2.OrID and t2.FileID <= #t2.FileID) As rnk
from #t2
order by OrID



Declare tCursor CURSOR LOCAL FORWARD_ONLY STATIC READ_ONLY For
select MasterFid
	,OrID
	,FileID
	,orType
	,orid
	from #t3
WHERE rnk < 4

--select MasterFid,OrID,FileID,orType,orid from #t3 WHERE rnk < 4

--************************************
	open tCursor
	--drop table #t2
	--drop table #t3
	Declare @MasterFid INT, @orId INT;

	set @MasterFid =0
	set @orId=0
	Declare
		@DocId int
		, @FileID int
		, @orType int
		, @tDir nvarchar(256)
		, @oTyp int
		set @oTyp=230
	Declare @InstanceServerCommandKey NVarchar(255)
	Set @InstanceServerCommandKey = ' -S'+cast(ServerProperty('ServerName') as varchar)+' '

	fetch next from tCursor Into @MasterFid, @DocId, @FileID, @orType, @orId
	while @@FETCH_STATUS <> -1
	begin
		set @FileName=CAST(@FileID as nvarchar)+ '_' + CAST(@MasterFid as nvarchar)+CAST(@orID as nvarchar)

		Set @tcmd = 'BCP "Select Attached.FileData From '+ DB_NAME() + '..DS_DocAttachments AS Attached '
		+ ' Where Attached.MasterFid = ' + Cast(@MasterFid As nvarchar(30))
		+ '   And Attached.DocId = ' + Cast(@DocId As nvarchar(30))
		+ '   And Attached.FileID = ' + Cast(@FileId As NVarChar(30))

		+'" queryout ' + '"'+ @BaseDir +
		@FileName+@exi+
		+ '" -f"' + @BaseDir + 'tscript.fmt" ' + @InstanceServerCommandKey + ' -T '
		--print '@tcmd=' + @tcmd

		EXEC master..xp_cmdshell @tcmd, no_output

		Fetch Next From tCursor Into @MasterFid, @DocId, @FileID, @orType, @orId
	end
	Close tCursor
	Deallocate	tCursor
	Return -1

end
*/