// ============================================================================
// ابرنرم‌افزار یکپارچه مدیریت تنخواه، هزینه‌های روزانه، ۳ انبار، بهای تمام‌شده (COGS) و فروش عمان
// نسخه جامع تجمیع‌شده (همه امکانات از ابتدا تا انتها در یک نرم‌افزار واحد):
// ۱. مدیریت تنخواه دریافتی از شرکت و هزینه‌های روزانه شخصی/کاری + سرفصل‌ها، موضوعات و فیلترهای سفارشی
// ۲. سامانه ۳ انبار مجزا و مرتبط با گردش زنده:
//    - انبار ۱: مواد اولیه اصلی (پنیر پیتزا بلوکی، کره فله و...) با هزینه حمل و میانگین موزون
//    - انبار ۲: ملزومات بسته‌بندی (کارتن، نایلون، لیبل و...) با کسر خودکار در تولید
//    - انبار ۳: محصولات نهایی آماده فروش با فرمول تولید (BOM) و کارت بهای تمام‌شده هر بسته و هر کیلو
// ۳. ثبت تولید کارمزدی (رنده پنیر / ریپک و لیبل‌زنی کره) با محاسبه خودکار افت و بهای تمام‌شده
// ۴. فروش به مشتریان (نام مشتری، مقدار و قیمت فروش توافقی)، سنجش زنده حاشیه سود/زیان و تقسیم سود شرکا (۱۰۰٪، ÷۲، ÷۳ یا دلخواه)
// ۵. گزارش‌گیری پیشرفته «تجمیعی» و «ریز» بدون محدودیت تاریخی (۷، ۱۰، ۱۵، ۳۰ روزه یا از تاریخ تا تاریخ) + خروجی Excel واحد مالی
// ۶. امنیت کامل رمز نسخه مادر (بدون نمایش رمز + قابلیت تغییر رمز) و اتصال ابری اینترنتی بین ۳ دستگاه (اندروید، ویندوز .exe و آیفون)
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const OmanUnifiedSuperApp());
}

class OmanUnifiedSuperApp extends StatelessWidget {
  const OmanUnifiedSuperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'سامانه جامع تنخواه، ۳ انبار، بهای تمام‌شده و فروش عمان',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0F766E),
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
      home: const UnifiedMasterPage(),
    );
  }
}

// ----------------------------------------------------------------------------
// مدل‌های بخش ۱: تنخواه و هزینه‌های روزانه
// ----------------------------------------------------------------------------
enum TxMode { expense, deposit }
enum ExpenseSource { petty, pocket, personal }
enum ReportViewMode { consolidated, detailed }

class CustomFilterDef {
  final String id;
  final String name;
  final List<String> options;

  CustomFilterDef({required this.id, required this.name, required this.options});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'options': options};

  factory CustomFilterDef.fromJson(Map<String, dynamic> j) => CustomFilterDef(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        options: (j['options'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      );
}

class TransactionRecord {
  final String id;
  final TxMode mode;
  final ExpenseSource source;
  final double amountOMR;
  final DateTime date;
  final String topic;
  final String category;
  final String title;
  final String note;
  final Map<String, String> customValues;

  TransactionRecord({
    required this.id,
    required this.mode,
    required this.source,
    required this.amountOMR,
    required this.date,
    required this.topic,
    required this.category,
    required this.title,
    this.note = '',
    this.customValues = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'mode': mode.name,
        'source': source.name,
        'amountOMR': amountOMR,
        'date': date.toIso8601String(),
        'topic': topic,
        'category': category,
        'title': title,
        'note': note,
        'customValues': customValues,
      };

  factory TransactionRecord.fromJson(Map<String, dynamic> j) => TransactionRecord(
        id: j['id']?.toString() ?? '',
        mode: j['mode'] == 'deposit' ? TxMode.deposit : TxMode.expense,
        source: ExpenseSource.values.firstWhere(
          (e) => e.name == j['source'],
          orElse: () => ExpenseSource.petty,
        ),
        amountOMR: (j['amountOMR'] as num?)?.toDouble() ?? 0.0,
        date: DateTime.tryParse(j['date']?.toString() ?? '') ?? DateTime.now(),
        topic: j['topic']?.toString() ?? '',
        category: j['category']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        note: j['note']?.toString() ?? '',
        customValues: (j['customValues'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, v.toString())),
      );
}

class ConsolidatedExpenseRow {
  final String groupTitle;
  final String subTitle;
  int count;
  double totalExpenseOMR;
  double totalDepositOMR;
  DateTime firstDate;
  DateTime lastDate;

  ConsolidatedExpenseRow({
    required this.groupTitle,
    required this.subTitle,
    required this.count,
    required this.totalExpenseOMR,
    required this.totalDepositOMR,
    required this.firstDate,
    required this.lastDate,
  });
}

// ----------------------------------------------------------------------------
// مدل‌های بخش ۲: سامانه ۳ انبار، بهای تمام‌شده صنعتی (BOM/COGS)، مشتریان و فروش
// ----------------------------------------------------------------------------
enum WarehouseType {
  rawMaterial, // انبار ۱: مواد اولیه اصلی
  packagingSupply, // انبار ۲: ملزومات بسته‌بندی (کارتن، نایلون، لیبل)
  finishedGood, // انبار ۳: محصول نهایی آماده فروش
}

class InventoryItem {
  final String id;
  final String name;
  final WarehouseType warehouse;
  final String unit;
  double unitWeightKg;
  double currentQty;
  double avgUnitCostOMR;
  double defaultSalePriceOMR;
  double defaultCartonPerUnit;
  double defaultNylonPerUnit;
  double defaultLabelPerUnit;

  InventoryItem({
    required this.id,
    required this.name,
    required this.warehouse,
    required this.unit,
    this.unitWeightKg = 1.0,
    this.currentQty = 0.0,
    this.avgUnitCostOMR = 0.0,
    this.defaultSalePriceOMR = 0.0,
    this.defaultCartonPerUnit = 0.1,
    this.defaultNylonPerUnit = 1.0,
    this.defaultLabelPerUnit = 1.0,
  });

  double get totalInventoryValueOMR => (currentQty > 0 ? currentQty : 0) * avgUnitCostOMR;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'warehouse': warehouse.name,
        'unit': unit,
        'unitWeightKg': unitWeightKg,
        'currentQty': currentQty,
        'avgUnitCostOMR': avgUnitCostOMR,
        'defaultSalePriceOMR': defaultSalePriceOMR,
        'defaultCartonPerUnit': defaultCartonPerUnit,
        'defaultNylonPerUnit': defaultNylonPerUnit,
        'defaultLabelPerUnit': defaultLabelPerUnit,
      };

  factory InventoryItem.fromJson(Map<String, dynamic> j) => InventoryItem(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        warehouse: WarehouseType.values.firstWhere(
          (e) => e.name == j['warehouse'],
          orElse: () => WarehouseType.rawMaterial,
        ),
        unit: j['unit']?.toString() ?? 'واحد',
        unitWeightKg: (j['unitWeightKg'] as num?)?.toDouble() ?? 1.0,
        currentQty: (j['currentQty'] as num?)?.toDouble() ?? 0.0,
        avgUnitCostOMR: (j['avgUnitCostOMR'] as num?)?.toDouble() ?? 0.0,
        defaultSalePriceOMR: (j['defaultSalePriceOMR'] as num?)?.toDouble() ?? 0.0,
        defaultCartonPerUnit: (j['defaultCartonPerUnit'] as num?)?.toDouble() ?? 0.1,
        defaultNylonPerUnit: (j['defaultNylonPerUnit'] as num?)?.toDouble() ?? 1.0,
        defaultLabelPerUnit: (j['defaultLabelPerUnit'] as num?)?.toDouble() ?? 1.0,
      );
}

class PurchaseInboundDoc {
  final String id;
  final DateTime date;
  final String itemId;
  final String itemName;
  final WarehouseType warehouse;
  final String unit;
  final double qty;
  final double purchaseUnitPriceOMR;
  final double freightAndCustomsOMR;
  final String note;

  PurchaseInboundDoc({
    required this.id,
    required this.date,
    required this.itemId,
    required this.itemName,
    required this.warehouse,
    required this.unit,
    required this.qty,
    required this.purchaseUnitPriceOMR,
    required this.freightAndCustomsOMR,
    this.note = '',
  });

  double get totalPurchaseBaseOMR => qty * purchaseUnitPriceOMR;
  double get totalLandedCostOMR => totalPurchaseBaseOMR + freightAndCustomsOMR;
  double get landedUnitCostOMR => qty > 0 ? totalLandedCostOMR / qty : 0.0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'itemId': itemId,
        'itemName': itemName,
        'warehouse': warehouse.name,
        'unit': unit,
        'qty': qty,
        'purchaseUnitPriceOMR': purchaseUnitPriceOMR,
        'freightAndCustomsOMR': freightAndCustomsOMR,
        'note': note,
      };

  factory PurchaseInboundDoc.fromJson(Map<String, dynamic> j) => PurchaseInboundDoc(
        id: j['id']?.toString() ?? '',
        date: DateTime.tryParse(j['date']?.toString() ?? '') ?? DateTime.now(),
        itemId: j['itemId']?.toString() ?? '',
        itemName: j['itemName']?.toString() ?? '',
        warehouse: WarehouseType.values.firstWhere(
          (e) => e.name == j['warehouse'],
          orElse: () => WarehouseType.rawMaterial,
        ),
        unit: j['unit']?.toString() ?? 'واحد',
        qty: (j['qty'] as num?)?.toDouble() ?? 0.0,
        purchaseUnitPriceOMR: (j['purchaseUnitPriceOMR'] as num?)?.toDouble() ?? 0.0,
        freightAndCustomsOMR: (j['freightAndCustomsOMR'] as num?)?.toDouble() ?? 0.0,
        note: j['note']?.toString() ?? '',
      );
}

class ProductionCostDoc {
  final String id;
  final DateTime date;
  final String rawItemId;
  final String rawItemName;
  final double rawQtyUsed;
  final double rawCostOMR;
  final String cartonItemId;
  final String cartonItemName;
  final double cartonQtyUsed;
  final double cartonCostOMR;
  final String nylonItemId;
  final String nylonItemName;
  final double nylonQtyUsed;
  final double nylonCostOMR;
  final String labelItemId;
  final String labelItemName;
  final double labelQtyUsed;
  final double labelCostOMR;
  final double factoryTollFeeOMR;
  final double transportAndOtherCostOMR;
  final String finishedItemId;
  final String finishedItemName;
  final String finishedUnit;
  final double finishedQtyProduced;
  final double finishedTotalWeightKg;
  final double wastageKg;
  final double totalBatchCostOMR;
  final double unitCostOMR;
  final double costPerKgOMR;
  final String note;

  ProductionCostDoc({
    required this.id,
    required this.date,
    required this.rawItemId,
    required this.rawItemName,
    required this.rawQtyUsed,
    required this.rawCostOMR,
    required this.cartonItemId,
    required this.cartonItemName,
    required this.cartonQtyUsed,
    required this.cartonCostOMR,
    required this.nylonItemId,
    required this.nylonItemName,
    required this.nylonQtyUsed,
    required this.nylonCostOMR,
    required this.labelItemId,
    required this.labelItemName,
    required this.labelQtyUsed,
    required this.labelCostOMR,
    required this.factoryTollFeeOMR,
    required this.transportAndOtherCostOMR,
    required this.finishedItemId,
    required this.finishedItemName,
    required this.finishedUnit,
    required this.finishedQtyProduced,
    required this.finishedTotalWeightKg,
    required this.wastageKg,
    required this.totalBatchCostOMR,
    required this.unitCostOMR,
    required this.costPerKgOMR,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'rawItemId': rawItemId,
        'rawItemName': rawItemName,
        'rawQtyUsed': rawQtyUsed,
        'rawCostOMR': rawCostOMR,
        'cartonItemId': cartonItemId,
        'cartonItemName': cartonItemName,
        'cartonQtyUsed': cartonQtyUsed,
        'cartonCostOMR': cartonCostOMR,
        'nylonItemId': nylonItemId,
        'nylonItemName': nylonItemName,
        'nylonQtyUsed': nylonQtyUsed,
        'nylonCostOMR': nylonCostOMR,
        'labelItemId': labelItemId,
        'labelItemName': labelItemName,
        'labelQtyUsed': labelQtyUsed,
        'labelCostOMR': labelCostOMR,
        'factoryTollFeeOMR': factoryTollFeeOMR,
        'transportAndOtherCostOMR': transportAndOtherCostOMR,
        'finishedItemId': finishedItemId,
        'finishedItemName': finishedItemName,
        'finishedUnit': finishedUnit,
        'finishedQtyProduced': finishedQtyProduced,
        'finishedTotalWeightKg': finishedTotalWeightKg,
        'wastageKg': wastageKg,
        'totalBatchCostOMR': totalBatchCostOMR,
        'unitCostOMR': unitCostOMR,
        'costPerKgOMR': costPerKgOMR,
        'note': note,
      };

  factory ProductionCostDoc.fromJson(Map<String, dynamic> j) => ProductionCostDoc(
        id: j['id']?.toString() ?? '',
        date: DateTime.tryParse(j['date']?.toString() ?? '') ?? DateTime.now(),
        rawItemId: j['rawItemId']?.toString() ?? '',
        rawItemName: j['rawItemName']?.toString() ?? '',
        rawQtyUsed: (j['rawQtyUsed'] as num?)?.toDouble() ?? 0.0,
        rawCostOMR: (j['rawCostOMR'] as num?)?.toDouble() ?? 0.0,
        cartonItemId: j['cartonItemId']?.toString() ?? '',
        cartonItemName: j['cartonItemName']?.toString() ?? '',
        cartonQtyUsed: (j['cartonQtyUsed'] as num?)?.toDouble() ?? 0.0,
        cartonCostOMR: (j['cartonCostOMR'] as num?)?.toDouble() ?? 0.0,
        nylonItemId: j['nylonItemId']?.toString() ?? '',
        nylonItemName: j['nylonItemName']?.toString() ?? '',
        nylonQtyUsed: (j['nylonQtyUsed'] as num?)?.toDouble() ?? 0.0,
        nylonCostOMR: (j['nylonCostOMR'] as num?)?.toDouble() ?? 0.0,
        labelItemId: j['labelItemId']?.toString() ?? '',
        labelItemName: j['labelItemName']?.toString() ?? '',
        labelQtyUsed: (j['labelQtyUsed'] as num?)?.toDouble() ?? 0.0,
        labelCostOMR: (j['labelCostOMR'] as num?)?.toDouble() ?? 0.0,
        factoryTollFeeOMR: (j['factoryTollFeeOMR'] as num?)?.toDouble() ?? 0.0,
        transportAndOtherCostOMR: (j['transportAndOtherCostOMR'] as num?)?.toDouble() ?? 0.0,
        finishedItemId: j['finishedItemId']?.toString() ?? '',
        finishedItemName: j['finishedItemName']?.toString() ?? '',
        finishedUnit: j['finishedUnit']?.toString() ?? 'بسته',
        finishedQtyProduced: (j['finishedQtyProduced'] as num?)?.toDouble() ?? 0.0,
        finishedTotalWeightKg: (j['finishedTotalWeightKg'] as num?)?.toDouble() ?? 0.0,
        wastageKg: (j['wastageKg'] as num?)?.toDouble() ?? 0.0,
        totalBatchCostOMR: (j['totalBatchCostOMR'] as num?)?.toDouble() ?? 0.0,
        unitCostOMR: (j['unitCostOMR'] as num?)?.toDouble() ?? 0.0,
        costPerKgOMR: (j['costPerKgOMR'] as num?)?.toDouble() ?? 0.0,
        note: j['note']?.toString() ?? '',
      );
}

class SaleProfitDoc {
  final String id;
  final DateTime date;
  final String finishedItemId;
  final String finishedItemName;
  final String unit;
  final double qtySold;
  final double unitSalePriceOMR;
  final double unitCogsOMR;
  final double deliveryExpenseOMR;
  final String customerName;
  final String paymentStatus;
  final int partnerSplitDivisor;
  final String note;

  SaleProfitDoc({
    required this.id,
    required this.date,
    required this.finishedItemId,
    required this.finishedItemName,
    required this.unit,
    required this.qtySold,
    required this.unitSalePriceOMR,
    required this.unitCogsOMR,
    required this.deliveryExpenseOMR,
    required this.customerName,
    required this.paymentStatus,
    required this.partnerSplitDivisor,
    this.note = '',
  });

  double get totalRevenueOMR => qtySold * unitSalePriceOMR;
  double get totalCogsOMR => (qtySold * unitCogsOMR) + deliveryExpenseOMR;
  double get netProfitOrLossOMR => totalRevenueOMR - totalCogsOMR;
  double get profitMarginPercent =>
      totalRevenueOMR > 0 ? (netProfitOrLossOMR / totalRevenueOMR) * 100.0 : 0.0;
  bool get isInLoss => netProfitOrLossOMR < -0.0005;

  double get myProfitShareOMR =>
      partnerSplitDivisor > 1 ? netProfitOrLossOMR / partnerSplitDivisor : netProfitOrLossOMR;
  double get partnersProfitShareOMR => netProfitOrLossOMR - myProfitShareOMR;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'finishedItemId': finishedItemId,
        'finishedItemName': finishedItemName,
        'unit': unit,
        'qtySold': qtySold,
        'unitSalePriceOMR': unitSalePriceOMR,
        'unitCogsOMR': unitCogsOMR,
        'deliveryExpenseOMR': deliveryExpenseOMR,
        'customerName': customerName,
        'paymentStatus': paymentStatus,
        'partnerSplitDivisor': partnerSplitDivisor,
        'note': note,
      };

  factory SaleProfitDoc.fromJson(Map<String, dynamic> j) => SaleProfitDoc(
        id: j['id']?.toString() ?? '',
        date: DateTime.tryParse(j['date']?.toString() ?? '') ?? DateTime.now(),
        finishedItemId: j['finishedItemId']?.toString() ?? '',
        finishedItemName: j['finishedItemName']?.toString() ?? '',
        unit: j['unit']?.toString() ?? 'بسته',
        qtySold: (j['qtySold'] as num?)?.toDouble() ?? 0.0,
        unitSalePriceOMR: (j['unitSalePriceOMR'] as num?)?.toDouble() ?? 0.0,
        unitCogsOMR: (j['unitCogsOMR'] as num?)?.toDouble() ?? 0.0,
        deliveryExpenseOMR: (j['deliveryExpenseOMR'] as num?)?.toDouble() ?? 0.0,
        customerName: j['customerName']?.toString() ?? '',
        paymentStatus: j['paymentStatus']?.toString() ?? 'نقدی / واریز بانکی',
        partnerSplitDivisor: (j['partnerSplitDivisor'] as num?)?.toInt() ?? 1,
        note: j['note']?.toString() ?? '',
      );
}

// ============================================================================
// صفحه اصلی ابرنرم‌افزار یکپارچه (هم تنخواه و هزینه‌ها + هم ۳ انبار، تولید، بهای تمام‌شده و فروش)
// ============================================================================
class UnifiedMasterPage extends StatefulWidget {
  const UnifiedMasterPage({super.key});

  @override
  State<UnifiedMasterPage> createState() => _UnifiedMasterPageState();
}

class _UnifiedMasterPageState extends State<UnifiedMasterPage> {
  int _selectedIndex = 0;

  // امنیت نسخه مادر و همگام‌سازی ابری (بدون هیچ‌گونه نمایش رمز روی صفحه)
  bool _isMasterAdmin = false;
  String? _masterPin;
  String _cloudSyncUrl = '';
  bool _isSyncing = false;
  String _lastSyncStatus = 'آماده اتصال ابری';

  // داده‌های بخش ۱: تنخواه و هزینه‌های روزانه
  List<String> _categories = [
    'خورد و خوراک و اقلام مصرفی',
    'آب و برق و قبوض (برق، آب، اینترنت)',
    'اجاره مسکن و اقامت',
    'ایاب و ذهاب و تاکسی',
    'اجاره خودرو و بنزین',
    'امور اداری، ویزا و ثبت شرکت',
    'ارسال نمونه و لجستیک',
    'تجهیزات و ملزومات کاری',
    'سایر هزینه‌ها',
  ];

  List<String> _topics = [
    'تنخواه جاری شرکت در عمان',
    'امور راه‌اندازی و ثبت شرکت/برند',
    'پروژه کارخانه و بسته‌بندی مسقط',
    'مخارج شخصی روزمره',
  ];

  List<CustomFilterDef> _customFilters = [
    CustomFilterDef(
      id: 'cf_payment',
      name: 'روش پرداخت',
      options: ['نقدی (Cash OMR)', 'کارت بانک مسقط', 'حواله / موبایل بانک'],
    ),
    CustomFilterDef(
      id: 'cf_receipt',
      name: 'وضعیت فاکتور',
      options: ['دارای فاکتور رسمی', 'رسید عادی', 'بدون رسید'],
    ),
  ];

  List<TransactionRecord> _transactions = [];

  // داده‌های بخش ۲: ۳ انبار، بهای تمام‌شده، مشتریان و فروش
  List<String> _customers = [
    'مشتری عمومی بازار مسقط',
    'رستوران‌ها و فست‌فودها',
    'سوپرمارکت‌ها و هایپرمارکت‌ها',
    'پخش عمده مواد غذایی',
  ];

  List<InventoryItem> _items = [
    InventoryItem(
      id: 'raw_cheese_block',
      name: 'پنیر پیتزا بلوکی (ماده اولیه)',
      warehouse: WarehouseType.rawMaterial,
      unit: 'کیلوگرم',
      unitWeightKg: 1.0,
      avgUnitCostOMR: 1.450,
    ),
    InventoryItem(
      id: 'raw_butter_bulk',
      name: 'کره فله / بلوکی (ماده اولیه)',
      warehouse: WarehouseType.rawMaterial,
      unit: 'کیلوگرم',
      unitWeightKg: 1.0,
      avgUnitCostOMR: 1.800,
    ),
    InventoryItem(
      id: 'pkg_carton',
      name: 'کارتن بسته‌بندی محصول',
      warehouse: WarehouseType.packagingSupply,
      unit: 'عدد',
      unitWeightKg: 0.0,
      avgUnitCostOMR: 0.250,
    ),
    InventoryItem(
      id: 'pkg_nylon',
      name: 'نایلون / پاکت بسته‌بندی',
      warehouse: WarehouseType.packagingSupply,
      unit: 'عدد / برگ',
      unitWeightKg: 0.0,
      avgUnitCostOMR: 0.035,
    ),
    InventoryItem(
      id: 'pkg_label',
      name: 'لیبل / برچسب محصول',
      warehouse: WarehouseType.packagingSupply,
      unit: 'عدد',
      unitWeightKg: 0.0,
      avgUnitCostOMR: 0.015,
    ),
    InventoryItem(
      id: 'fin_cheese_1kg',
      name: 'پنیر پیتزا رنده‌شده ۱ کیلویی',
      warehouse: WarehouseType.finishedGood,
      unit: 'بسته ۱ کیلویی',
      unitWeightKg: 1.0,
      avgUnitCostOMR: 1.700,
      defaultSalePriceOMR: 2.200,
      defaultCartonPerUnit: 0.1,
      defaultNylonPerUnit: 1.0,
      defaultLabelPerUnit: 1.0,
    ),
    InventoryItem(
      id: 'fin_cheese_500g',
      name: 'پنیر پیتزا رنده‌شده ۵۰۰ گرمی',
      warehouse: WarehouseType.finishedGood,
      unit: 'بسته ۵۰۰ گرمی',
      unitWeightKg: 0.5,
      avgUnitCostOMR: 0.900,
      defaultSalePriceOMR: 1.200,
      defaultCartonPerUnit: 0.05,
      defaultNylonPerUnit: 1.0,
      defaultLabelPerUnit: 1.0,
    ),
    InventoryItem(
      id: 'fin_butter_100g',
      name: 'کره ریپک و لیبل‌خورده ۱۰۰ گرمی',
      warehouse: WarehouseType.finishedGood,
      unit: 'بسته ۱۰۰ گرمی',
      unitWeightKg: 0.1,
      avgUnitCostOMR: 0.220,
      defaultSalePriceOMR: 0.300,
      defaultCartonPerUnit: 0.02,
      defaultNylonPerUnit: 1.0,
      defaultLabelPerUnit: 1.0,
    ),
    InventoryItem(
      id: 'fin_butter_250g',
      name: 'کره ریپک و لیبل‌خورده ۲۵۰ گرمی',
      warehouse: WarehouseType.finishedGood,
      unit: 'بسته ۲۵۰ گرمی',
      unitWeightKg: 0.25,
      avgUnitCostOMR: 0.520,
      defaultSalePriceOMR: 0.700,
      defaultCartonPerUnit: 0.025,
      defaultNylonPerUnit: 1.0,
      defaultLabelPerUnit: 1.0,
    ),
  ];

  List<PurchaseInboundDoc> _inbounds = [];
  List<ProductionCostDoc> _productions = [];
  List<SaleProfitDoc> _sales = [];

  // کنترلرهای فرم تنخواه و هزینه روزانه
  String? _editingTxId;
  TxMode _formMode = TxMode.expense;
  ExpenseSource _formSource = ExpenseSource.petty;
  final TextEditingController _txAmountCtrl = TextEditingController();
  final TextEditingController _txTitleCtrl = TextEditingController();
  final TextEditingController _txNoteCtrl = TextEditingController();
  DateTime _txDate = DateTime.now();
  late String _selectedTopic;
  late String _selectedCategory;
  final Map<String, String> _selectedCustomValues = {};

  // کنترلرهای فرم انبار و تولید کارمزدی
  int _warehouseSubTab = 0; // 0 = موجودی ۳ انبار | 1 = ورود کالا به انبار ۱و۲ | 2 = تولید کارمزدی و BOM
  WarehouseType _inboundWhTarget = WarehouseType.rawMaterial;
  String? _selectedInboundItemId;
  final TextEditingController _inbQtyCtrl = TextEditingController();
  final TextEditingController _inbPriceCtrl = TextEditingController();
  final TextEditingController _inbFreightCtrl = TextEditingController(text: '0');
  final TextEditingController _inbNoteCtrl = TextEditingController();

  String? _prodRawId;
  String? _prodFinId;
  String? _prodCartonId;
  String? _prodNylonId;
  String? _prodLabelId;
  final TextEditingController _prodRawQtyCtrl = TextEditingController();
  final TextEditingController _prodFinQtyCtrl = TextEditingController();
  final TextEditingController _prodCartonQtyCtrl = TextEditingController();
  final TextEditingController _prodNylonQtyCtrl = TextEditingController();
  final TextEditingController _prodLabelQtyCtrl = TextEditingController();
  final TextEditingController _prodTollFeeCtrl = TextEditingController(text: '0');
  final TextEditingController _prodTransportCtrl = TextEditingController(text: '0');
  final TextEditingController _prodNoteCtrl = TextEditingController();

  // کنترلرهای فرم فروش و تقسیم سود شرکا
  String? _saleFinId;
  String? _saleCustomer;
  final TextEditingController _saleQtyCtrl = TextEditingController();
  final TextEditingController _salePriceCtrl = TextEditingController();
  final TextEditingController _saleDeliveryCostCtrl = TextEditingController(text: '0');
  String _salePaymentStatus = 'نقدی / واریز بانکی';
  int _salePartnerDivisor = 1;
  final TextEditingController _customDivisorCtrl = TextEditingController(text: '2');
  final TextEditingController _saleNoteCtrl = TextEditingController();

  // کنترلرهای گزارش‌گیری جامع (تنخواه + انبار و سود و زیان)
  int _reportSectionTab = 0; // 0 = گزارش تجمیعی/ریز تنخواه و هزینه‌ها | 1 = صورت سود و زیان، مشتریان و بهای تمام‌شده
  ReportViewMode _reportViewMode = ReportViewMode.consolidated;
  DateTime? _repFromDate;
  DateTime? _repToDate;
  final TextEditingController _fromDateTextCtrl = TextEditingController();
  final TextEditingController _toDateTextCtrl = TextEditingController();
  String _repTopicFilter = 'all';
  String _repCategoryFilter = 'all';
  String _repCustomerFilter = 'all';
  int _globalReportPartnerDivisor = 2;

  List<InventoryItem> get _rawList =>
      _items.where((i) => i.warehouse == WarehouseType.rawMaterial).toList();
  List<InventoryItem> get _pkgList =>
      _items.where((i) => i.warehouse == WarehouseType.packagingSupply).toList();
  List<InventoryItem> get _finList =>
      _items.where((i) => i.warehouse == WarehouseType.finishedGood).toList();

  @override
  void initState() {
    super.initState();
    _selectedTopic = _topics.first;
    _selectedCategory = _categories.first;
    _syncDefaults();
    _loadLocalData();
  }

  void _syncDefaults() {
    for (final cf in _customFilters) {
      if (!_selectedCustomValues.containsKey(cf.id) && cf.options.isNotEmpty) {
        _selectedCustomValues[cf.id] = cf.options.first;
      }
    }
    if (_customers.isNotEmpty) _saleCustomer ??= _customers.first;
    final targetList = _inboundWhTarget == WarehouseType.rawMaterial ? _rawList : _pkgList;
    if (targetList.isNotEmpty) {
      if (_selectedInboundItemId == null || !targetList.any((e) => e.id == _selectedInboundItemId)) {
        _selectedInboundItemId = targetList.first.id;
        _inbPriceCtrl.text = targetList.first.avgUnitCostOMR.toStringAsFixed(3);
      }
    }
    if (_rawList.isNotEmpty) _prodRawId ??= _rawList.first.id;
    if (_pkgList.isNotEmpty) {
      _prodCartonId ??= _pkgList.firstWhere((e) => e.name.contains('کارتن'), orElse: () => _pkgList.first).id;
      _prodNylonId ??= _pkgList.firstWhere((e) => e.name.contains('نایلون'), orElse: () => _pkgList.first).id;
      _prodLabelId ??= _pkgList.firstWhere((e) => e.name.contains('لیبل'), orElse: () => _pkgList.first).id;
    }
    if (_finList.isNotEmpty) {
      _prodFinId ??= _finList.first.id;
      if (_saleFinId == null || !_finList.any((e) => e.id == _saleFinId)) {
        _saleFinId = _finList.first.id;
        _salePriceCtrl.text = _finList.first.defaultSalePriceOMR.toStringAsFixed(3);
      }
    }
  }

  File _getLocalDbFile() {
    final dir = Directory.systemTemp;
    return File('${dir.path}/oman_unified_super_app_v1.json');
  }

  Future<void> _loadLocalData() async {
    try {
      final f = _getLocalDbFile();
      if (await f.exists()) {
        final content = await f.readAsString();
        _applyJsonState(jsonDecode(content), fromCloud: false);
      }
    } catch (_) {}
  }

  Future<void> _saveLocalData() async {
    try {
      final f = _getLocalDbFile();
      await f.writeAsString(jsonEncode(_exportStateJson(includeLocalAuth: true)));
    } catch (_) {}
  }

  Map<String, dynamic> _exportStateJson({required bool includeLocalAuth}) {
    final map = <String, dynamic>{
      'updatedAt': DateTime.now().toIso8601String(),
      'categories': _categories,
      'topics': _topics,
      'customFilters': _customFilters.map((e) => e.toJson()).toList(),
      'transactions': _transactions.map((e) => e.toJson()).toList(),
      'customers': _customers,
      'items': _items.map((e) => e.toJson()).toList(),
      'inbounds': _inbounds.map((e) => e.toJson()).toList(),
      'productions': _productions.map((e) => e.toJson()).toList(),
      'sales': _sales.map((e) => e.toJson()).toList(),
    };
    if (includeLocalAuth) {
      map['masterPin'] = _masterPin;
      map['isMasterAdmin'] = _isMasterAdmin;
      map['cloudSyncUrl'] = _cloudSyncUrl;
    }
    return map;
  }

  void _applyJsonState(Map<String, dynamic> data, {required bool fromCloud}) {
    setState(() {
      if (!fromCloud) {
        if (data['masterPin'] != null) _masterPin = data['masterPin'].toString();
        if (data['isMasterAdmin'] is bool) _isMasterAdmin = data['isMasterAdmin'] as bool;
        if (data['cloudSyncUrl'] != null) _cloudSyncUrl = data['cloudSyncUrl'].toString();
      }
      if (data['categories'] is List) {
        final l = (data['categories'] as List).map((e) => e.toString()).toList();
        if (l.isNotEmpty) _categories = l;
      }
      if (data['topics'] is List) {
        final l = (data['topics'] as List).map((e) => e.toString()).toList();
        if (l.isNotEmpty) _topics = l;
      }
      if (data['customFilters'] is List) {
        _customFilters = (data['customFilters'] as List)
            .map((e) => CustomFilterDef.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      if (data['transactions'] is List) {
        _transactions = (data['transactions'] as List)
            .map((e) => TransactionRecord.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      if (data['customers'] is List) {
        final c = (data['customers'] as List).map((e) => e.toString()).toList();
        if (c.isNotEmpty) _customers = c;
      }
      if (data['items'] is List) {
        final list = (data['items'] as List)
            .map((e) => InventoryItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        if (list.isNotEmpty) _items = list;
      }
      if (data['inbounds'] is List) {
        _inbounds = (data['inbounds'] as List)
            .map((e) => PurchaseInboundDoc.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      if (data['productions'] is List) {
        _productions = (data['productions'] as List)
            .map((e) => ProductionCostDoc.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      if (data['sales'] is List) {
        _sales = (data['sales'] as List)
            .map((e) => SaleProfitDoc.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      _syncDefaults();
    });
  }

  Future<void> _pushToCloud() async {
    if (!_isMasterAdmin || _cloudSyncUrl.trim().isEmpty) return;
    setState(() {
      _isSyncing = true;
      _lastSyncStatus = 'در حال ارسال به فضای ابری...';
    });
    try {
      final uri = Uri.parse(_cloudSyncUrl.trim());
      final client = HttpClient();
      final req = await client.putUrl(uri);
      req.headers.set('Content-Type', 'application/json; charset=utf-8');
      req.add(utf8.encode(jsonEncode(_exportStateJson(includeLocalAuth: false))));
      final resp = await req.close();
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        setState(() => _lastSyncStatus = '✅ همگام‌سازی ابری موفق');
      }
      client.close();
    } catch (_) {
      setState(() => _lastSyncStatus = 'ذخیره در حافظه دستگاه');
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  Future<void> _pullFromCloud() async {
    if (_cloudSyncUrl.trim().isEmpty) {
      _showMsg('لطفاً ابتدا آدرس ابری (Cloud URL) را در تنظیمات وارد کنید.');
      return;
    }
    setState(() {
      _isSyncing = true;
      _lastSyncStatus = 'در حال دریافت اطلاعات از اینترنت...';
    });
    try {
      final uri = Uri.parse(_cloudSyncUrl.trim());
      final client = HttpClient();
      final req = await client.getUrl(uri);
      final resp = await req.close();
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final body = await resp.transform(utf8.decoder).join();
        if (body.isNotEmpty && body != 'null') {
          final decoded = jsonDecode(body);
          if (decoded is Map<String, dynamic>) {
            _applyJsonState(decoded, fromCloud: true);
            await _saveLocalData();
            setState(() => _lastSyncStatus = '✅ آخرین اطلاعات دریافت شد');
            _showMsg('✅ اطلاعات تنخواه، ۳ انبار و فروش از اینترنت به‌روز شد.');
          }
        }
      }
      client.close();
    } catch (_) {
      _showMsg('خطا در اتصال به اینترنت');
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  String _fmtOMR(double v) => v.toStringAsFixed(3);
  String _fmtQty(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  double get _totalPettyIn => _transactions
      .where((t) => t.mode == TxMode.deposit)
      .fold(0.0, (s, t) => s + t.amountOMR);
  double get _totalPettyOut => _transactions
      .where((t) => t.mode == TxMode.expense && t.source == ExpenseSource.petty)
      .fold(0.0, (s, t) => s + t.amountOMR);
  double get _pettyBalance => _totalPettyIn - _totalPettyOut;

  double get _totalSalesRevenueOMR => _sales.fold(0.0, (s, r) => s + r.totalRevenueOMR);
  double get _totalNetProfitOMR => _sales.fold(0.0, (s, r) => s + r.netProfitOrLossOMR);

  // ==========================================================================
  // پنجره امن مدیریت رمز نسخه مادر (بدون نمایش رمز روی صفحه + قابلیت تغییر رمز)
  // ==========================================================================
  void _showSecurityAndCloudDialog() {
    final pinInputCtrl = TextEditingController();
    final currentPinCtrl = TextEditingController();
    final newPinCtrl = TextEditingController();
    final confirmPinCtrl = TextEditingController();
    final cloudCtrl = TextEditingController(text: _cloudSyncUrl);

    showDialog(
      context: context,
      builder: (ctx) {
        final isFirstTimePinSetup = (_masterPin == null || _masterPin!.isEmpty);
        return AlertDialog(
          title: Text(_isMasterAdmin
              ? '👑 تنظیمات امنیتی نسخه مادر و فضای ابری'
              : '🔒 اتصال ابری و ورود به نسخه مادر'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _isMasterAdmin ? const Color(0xFFDCFCE7) : const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _isMasterAdmin
                        ? 'وضعیت فعلی: 👑 نسخه مادر (دسترسی کامل ثبت تنخواه، انبار، تولید و فروش)'
                        : 'وضعیت فعلی: 👁️ نسخه مشاهده‌گر و واحد مالی (فقط رویت و گزارش‌گیری بدون امکان تغییر اعداد)',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cloudCtrl,
                  decoration: const InputDecoration(
                    labelText: 'آدرس اینترنتی پایگاه داده ابری (Cloud Sync URL)',
                    hintText: 'https://your-db.firebaseio.com/oman_unified.json',
                    border: OutlineInputBorder(),
                  ),
                ),
                const Divider(height: 24),
                if (!_isMasterAdmin) ...[
                  Text(
                    isFirstTimePinSetup
                        ? '🔑 تعریف اولیه رمز نسخه مادر (فقط روی گوشی خودتان یک رمز دلخواه تعیین کنید):'
                        : '🔑 ورود رمز نسخه مادر (ویژه مدیر):',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: pinInputCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: isFirstTimePinSetup
                          ? 'رمز دلخواه جدید خود را وارد کنید (حداقل ۴ کاراکتر)'
                          : 'رمز نسخه مادر را وارد کنید',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ] else ...[
                  const Text(
                    '🔑 تغییر رمز نسخه مادر:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  if (!isFirstTimePinSetup) ...[
                    TextField(
                      controller: currentPinCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'رمز فعلی', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: newPinCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'رمز جدید', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: confirmPinCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'تکرار رمز جدید', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      if (!isFirstTimePinSetup && currentPinCtrl.text.trim() != _masterPin) {
                        _showMsg('❌ رمز فعلی نادرست است.');
                        return;
                      }
                      if (newPinCtrl.text.trim().length < 4) {
                        _showMsg('رمز جدید باید حداقل ۴ رقم یا کاراکتر باشد.');
                        return;
                      }
                      if (newPinCtrl.text.trim() != confirmPinCtrl.text.trim()) {
                        _showMsg('❌ رمز جدید و تکرار آن یکسان نیستند.');
                        return;
                      }
                      setState(() => _masterPin = newPinCtrl.text.trim());
                      _saveLocalData();
                      Navigator.pop(ctx);
                      _showMsg('✅ رمز نسخه مادر با موفقیت تغییر کرد.');
                    },
                    icon: const Icon(Icons.key),
                    label: const Text('ثبت تغییر رمز مادر'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (_isMasterAdmin)
              TextButton(
                onPressed: () {
                  setState(() {
                    _isMasterAdmin = false;
                    _cloudSyncUrl = cloudCtrl.text.trim();
                    _selectedIndex = 0;
                  });
                  _saveLocalData();
                  Navigator.pop(ctx);
                  _showMsg('برنامه روی حالت «فقط رویت (مشاهده‌گر)» قفل شد.');
                },
                child: const Text('قفل کردن روی حالت مشاهده‌گر'),
              ),
            TextButton(
              onPressed: () {
                setState(() => _cloudSyncUrl = cloudCtrl.text.trim());
                _saveLocalData();
                Navigator.pop(ctx);
              },
              child: const Text('ذخیره آدرس ابری و بستن'),
            ),
            if (!_isMasterAdmin)
              FilledButton(
                onPressed: () {
                  setState(() => _cloudSyncUrl = cloudCtrl.text.trim());
                  final entered = pinInputCtrl.text.trim();
                  if (isFirstTimePinSetup) {
                    if (entered.length < 4) {
                      _showMsg('لطفاً حداقل ۴ رقم یا کاراکتر برای رمز مادر وارد کنید.');
                      return;
                    }
                    setState(() {
                      _masterPin = entered;
                      _isMasterAdmin = true;
                    });
                    _saveLocalData();
                    Navigator.pop(ctx);
                    _showMsg('👑 رمز اختصاصی شما ثبت شد و نسخه مادر فعال گردید.');
                  } else if (entered == _masterPin) {
                    setState(() => _isMasterAdmin = true);
                    _saveLocalData();
                    Navigator.pop(ctx);
                    _showMsg('👑 نسخه مادر فعال شد.');
                  } else {
                    _saveLocalData();
                    Navigator.pop(ctx);
                    if (entered.isNotEmpty) _showMsg('❌ رمز واردشده صحیح نیست.');
                  }
                },
                child: Text(isFirstTimePinSetup ? 'ثبت رمز و فعال‌سازی نسخه مادر' : 'ورود به نسخه مادر'),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      _buildPettyCashAndExpensesTab(),
      _buildThreeWarehousesAndBomTab(),
      if (_isMasterAdmin) _buildSalesProfitAndPartnerTab(),
      _buildUnifiedReportsAndCfoTab(),
      if (_isMasterAdmin) _buildCustomizeSettingsTab(),
    ];

    final navDestinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.account_balance_wallet_outlined),
        label: 'تنخواه و هزینه‌ها',
      ),
      const NavigationDestination(
        icon: Icon(Icons.warehouse_outlined),
        label: '۳ انبار و تولید',
      ),
      if (_isMasterAdmin)
        const NavigationDestination(
          icon: Icon(Icons.point_of_sale_outlined),
          label: 'فروش و سود/شریک',
        ),
      const NavigationDestination(
        icon: Icon(Icons.assessment_outlined),
        label: 'گزارش تجمیعی و مالی',
      ),
      if (_isMasterAdmin)
        const NavigationDestination(
          icon: Icon(Icons.tune_outlined),
          label: 'سرفصل و فیلترها',
        ),
    ];

    if (_selectedIndex >= tabs.length) _selectedIndex = 0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _isMasterAdmin ? const Color(0xFF0F766E) : const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isMasterAdmin
                  ? '👑 ابرنرم‌افزار تنخواه، ۳ انبار، تولید و فروش عمان (نسخه مادر)'
                  : '👁️ سامانه تنخواه، انبار و مالی عمان (نسخه مشاهده‌گر و واحد مالی)',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
            ),
            Text(_lastSyncStatus, style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'دریافت آخرین اطلاعات از اینترنت',
            onPressed: _isSyncing ? null : _pullFromCloud,
            icon: const Icon(Icons.cloud_download_outlined),
          ),
          if (_isMasterAdmin)
            IconButton(
              tooltip: 'ارسال به فضای ابری',
              onPressed: _isSyncing ? null : _pushToCloud,
              icon: const Icon(Icons.cloud_upload_outlined),
            ),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: _showSecurityAndCloudDialog,
            icon: Icon(_isMasterAdmin ? Icons.vpn_key : Icons.lock_outline, size: 18),
            label: Text(_isMasterAdmin ? 'رمز مادر' : 'ورود مادر'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildHeaderMetric(
                  _pettyBalance >= 0 ? 'مانده تنخواه' : 'طلب تنخواه',
                  '${_fmtOMR(_pettyBalance.abs())} OMR',
                ),
                _buildHeaderMetric('کل فروش بازار', '${_fmtOMR(_totalSalesRevenueOMR)} OMR'),
                _buildHeaderMetric('سود خالص فروش', '${_fmtOMR(_totalNetProfitOMR)} OMR'),
              ],
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: tabs[_selectedIndex],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
        destinations: navDestinations,
      ),
    );
  }

  Widget _buildHeaderMetric(String label, String val) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 2),
        Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5)),
      ],
    );
  }

  // ==========================================================================
  // تب ۱: مدیریت تنخواه شرکت و هزینه‌های روزانه شخصی/کاری
  // ==========================================================================
  void _saveExpenseOrDeposit() {
    if (!_isMasterAdmin) return;
    final amt = double.tryParse(_txAmountCtrl.text.trim());
    final title = _txTitleCtrl.text.trim();
    if (amt == null || amt <= 0 || title.isEmpty) {
      _showMsg('لطفاً مبلغ (OMR) و شرح را وارد کنید.');
      return;
    }

    final rec = TransactionRecord(
      id: _editingTxId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      mode: _formMode,
      source: _formSource,
      amountOMR: double.parse(amt.toStringAsFixed(3)),
      date: _txDate,
      topic: _selectedTopic,
      category: _formMode == TxMode.deposit ? 'دریافت تنخواه از شرکت' : _selectedCategory,
      title: title,
      note: _txNoteCtrl.text.trim(),
      customValues: Map<String, String>.from(_selectedCustomValues),
    );

    setState(() {
      if (_editingTxId != null) {
        final idx = _transactions.indexWhere((t) => t.id == _editingTxId);
        if (idx != -1) _transactions[idx] = rec;
        _editingTxId = null;
      } else {
        _transactions.insert(0, rec);
      }
      _txAmountCtrl.clear();
      _txTitleCtrl.clear();
      _txNoteCtrl.clear();
    });
    _saveLocalData();
    _pushToCloud();
    _showMsg('✅ در بخش تنخواه و هزینه‌ها ثبت شد.');
  }

  Widget _buildPettyCashAndExpensesTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        if (_isMasterAdmin)
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '➕ ثبت هزینه روزانه یا دریافت تنخواه از شرکت',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<TxMode>(
                    segments: const [
                      ButtonSegment(value: TxMode.expense, label: Text('💸 ثبت هزینه کرد')),
                      ButtonSegment(value: TxMode.deposit, label: Text('💰 دریافت تنخواه از شرکت')),
                    ],
                    selected: {_formMode},
                    onSelectionChanged: (s) => setState(() => _formMode = s.first),
                  ),
                  const SizedBox(height: 10),
                  if (_formMode == TxMode.expense) ...[
                    SegmentedButton<ExpenseSource>(
                      segments: const [
                        ButtonSegment(value: ExpenseSource.petty, label: Text('از تنخواه شرکت')),
                        ButtonSegment(value: ExpenseSource.pocket, label: Text('از جیب برای کار')),
                        ButtonSegment(value: ExpenseSource.personal, label: Text('هزینه شخصی')),
                      ],
                      selected: {_formSource},
                      onSelectionChanged: (s) => setState(() => _formSource = s.first),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _txAmountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'مبلغ (ریال عمان - OMR) *',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                          onPressed: () async {
                            final p = await showDatePicker(
                              context: context,
                              initialDate: _txDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                            );
                            if (p != null) setState(() => _txDate = p);
                          },
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(_fmtDate(_txDate)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedTopic,
                          items: _topics.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                          onChanged: (v) => setState(() => _selectedTopic = v!),
                          decoration: const InputDecoration(labelText: 'موضوع', border: OutlineInputBorder()),
                        ),
                      ),
                      if (_formMode == TxMode.expense) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedCategory,
                            items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                            onChanged: (v) => setState(() => _selectedCategory = v!),
                            decoration: const InputDecoration(labelText: 'سرفصل هزینه کرد', border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _txTitleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'عنوان / شرح (مثلاً: بنزین، خرید خوراکی، قبض برق...)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ..._customFilters.map((cf) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DropdownButtonFormField<String>(
                          value: _selectedCustomValues[cf.id],
                          items: cf.options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
                          onChanged: (v) => setState(() => _selectedCustomValues[cf.id] = v!),
                          decoration: InputDecoration(labelText: cf.name, border: const OutlineInputBorder()),
                        ),
                      )),
                  FilledButton.icon(
                    onPressed: _saveExpenseOrDeposit,
                    icon: const Icon(Icons.check),
                    label: const Text('ثبت در دفتر تنخواه و هزینه‌ها'),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📋 آخرین تراکنش‌های تنخواه و هزینه‌های روزانه:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                const Divider(),
                if (_transactions.isEmpty)
                  const Text('هنوز تراکنشی در بخش تنخواه ثبت نشده است.')
                else
                  ..._transactions.take(15).map((t) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${_fmtDate(t.date)} | ${t.topic} | ${t.category}'),
                        trailing: Text(
                          '${t.mode == TxMode.deposit ? '+' : ''}${_fmtOMR(t.amountOMR)} OMR',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: t.mode == TxMode.deposit ? Colors.green[700] : Colors.black87,
                          ),
                        ),
                      )),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // تب ۲: سامانه ۳ انبار مجزا + ورود بار + تولید کارمزدی و بهای تمام‌شده (BOM)
  // ==========================================================================
  void _autoCalcBom(String finQtyText) {
    final finQty = double.tryParse(finQtyText.trim()) ?? 0.0;
    if (finQty <= 0 || _prodFinId == null) return;
    final finItem = _finList.firstWhere((e) => e.id == _prodFinId!, orElse: () => _finList.first);
    setState(() {
      _prodCartonQtyCtrl.text = (finQty * finItem.defaultCartonPerUnit).toStringAsFixed(1);
      _prodNylonQtyCtrl.text = (finQty * finItem.defaultNylonPerUnit).toStringAsFixed(0);
      _prodLabelQtyCtrl.text = (finQty * finItem.defaultLabelPerUnit).toStringAsFixed(0);
    });
  }

  Map<String, double> _previewLiveBatchCost() {
    final rawQty = double.tryParse(_prodRawQtyCtrl.text.trim()) ?? 0.0;
    final finQty = double.tryParse(_prodFinQtyCtrl.text.trim()) ?? 0.0;
    final cartonQty = double.tryParse(_prodCartonQtyCtrl.text.trim()) ?? 0.0;
    final nylonQty = double.tryParse(_prodNylonQtyCtrl.text.trim()) ?? 0.0;
    final labelQty = double.tryParse(_prodLabelQtyCtrl.text.trim()) ?? 0.0;
    final tollFee = double.tryParse(_prodTollFeeCtrl.text.trim()) ?? 0.0;
    final transport = double.tryParse(_prodTransportCtrl.text.trim()) ?? 0.0;

    final rawItem = _items.firstWhere((e) => e.id == _prodRawId, orElse: () => _rawList.first);
    final finItem = _items.firstWhere((e) => e.id == _prodFinId, orElse: () => _finList.first);
    final cartonItem = _items.firstWhere((e) => e.id == _prodCartonId, orElse: () => _pkgList.first);
    final nylonItem = _items.firstWhere((e) => e.id == _prodNylonId, orElse: () => _pkgList.first);
    final labelItem = _items.firstWhere((e) => e.id == _prodLabelId, orElse: () => _pkgList.first);

    final rawCost = rawQty * rawItem.avgUnitCostOMR;
    final cartonCost = cartonQty * cartonItem.avgUnitCostOMR;
    final nylonCost = nylonQty * nylonItem.avgUnitCostOMR;
    final labelCost = labelQty * labelItem.avgUnitCostOMR;
    final totalBatchCost = rawCost + cartonCost + nylonCost + labelCost + tollFee + transport;

    final unitCost = finQty > 0 ? totalBatchCost / finQty : 0.0;
    final totalFinWeightKg = finQty * finItem.unitWeightKg;
    final costPerKg = totalFinWeightKg > 0 ? totalBatchCost / totalFinWeightKg : 0.0;
    final inputWeightKg = rawQty * rawItem.unitWeightKg;
    final wastageKg = (inputWeightKg - totalFinWeightKg) > 0 ? (inputWeightKg - totalFinWeightKg) : 0.0;

    return {
      'rawCost': rawCost,
      'cartonCost': cartonCost,
      'nylonCost': nylonCost,
      'labelCost': labelCost,
      'packagingTotal': cartonCost + nylonCost + labelCost,
      'overheadTotal': tollFee + transport,
      'totalBatchCost': totalBatchCost,
      'unitCost': unitCost,
      'costPerKg': costPerKg,
      'totalFinWeightKg': totalFinWeightKg,
      'wastageKg': wastageKg,
    };
  }

  void _savePurchaseInbound() {
    if (!_isMasterAdmin) return;
    final qty = double.tryParse(_inbQtyCtrl.text.trim());
    final price = double.tryParse(_inbPriceCtrl.text.trim());
    final freight = double.tryParse(_inbFreightCtrl.text.trim()) ?? 0.0;
    if (_selectedInboundItemId == null || qty == null || qty <= 0 || price == null || price < 0) {
      _showMsg('لطفاً کالا، مقدار و قیمت واحد را وارد کنید.');
      return;
    }
    final item = _items.firstWhere((e) => e.id == _selectedInboundItemId!);
    final doc = PurchaseInboundDoc(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: DateTime.now(),
      itemId: item.id,
      itemName: item.name,
      warehouse: item.warehouse,
      unit: item.unit,
      qty: qty,
      purchaseUnitPriceOMR: price,
      freightAndCustomsOMR: freight,
      note: _inbNoteCtrl.text.trim(),
    );

    setState(() {
      final oldVal = (item.currentQty > 0 ? item.currentQty : 0.0) * item.avgUnitCostOMR;
      final newTotalQty = (item.currentQty > 0 ? item.currentQty : 0.0) + qty;
      if (newTotalQty > 0) {
        item.avgUnitCostOMR = (oldVal + doc.totalLandedCostOMR) / newTotalQty;
      }
      item.currentQty += qty;
      _inbounds.insert(0, doc);
      _inbQtyCtrl.clear();
      _inbFreightCtrl.text = '0';
      _inbNoteCtrl.clear();
      _warehouseSubTab = 0;
    });
    _saveLocalData();
    _pushToCloud();
    _showMsg('✅ ورود به انبار ثبت شد و میانگین موزون بهای تمام‌شده به‌روز گردید.');
  }

  void _saveProductionBatch() {
    if (!_isMasterAdmin) return;
    final rawQty = double.tryParse(_prodRawQtyCtrl.text.trim()) ?? 0.0;
    final finQty = double.tryParse(_prodFinQtyCtrl.text.trim()) ?? 0.0;
    final cartonQty = double.tryParse(_prodCartonQtyCtrl.text.trim()) ?? 0.0;
    final nylonQty = double.tryParse(_prodNylonQtyCtrl.text.trim()) ?? 0.0;
    final labelQty = double.tryParse(_prodLabelQtyCtrl.text.trim()) ?? 0.0;
    final tollFee = double.tryParse(_prodTollFeeCtrl.text.trim()) ?? 0.0;
    final transport = double.tryParse(_prodTransportCtrl.text.trim()) ?? 0.0;

    if (rawQty <= 0 || finQty <= 0 || _prodRawId == null || _prodFinId == null) {
      _showMsg('لطفاً مقدار ماده اولیه و تعداد محصول نهایی تولیدشده را وارد کنید.');
      return;
    }

    final rawItem = _items.firstWhere((e) => e.id == _prodRawId!);
    final finItem = _items.firstWhere((e) => e.id == _prodFinId!);
    final cartonItem = _items.firstWhere((e) => e.id == _prodCartonId!);
    final nylonItem = _items.firstWhere((e) => e.id == _prodNylonId!);
    final labelItem = _items.firstWhere((e) => e.id == _prodLabelId!);
    final calc = _previewLiveBatchCost();

    final doc = ProductionCostDoc(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: DateTime.now(),
      rawItemId: rawItem.id,
      rawItemName: rawItem.name,
      rawQtyUsed: rawQty,
      rawCostOMR: calc['rawCost']!,
      cartonItemId: cartonItem.id,
      cartonItemName: cartonItem.name,
      cartonQtyUsed: cartonQty,
      cartonCostOMR: calc['cartonCost']!,
      nylonItemId: nylonItem.id,
      nylonItemName: nylonItem.name,
      nylonQtyUsed: nylonQty,
      nylonCostOMR: calc['nylonCost']!,
      labelItemId: labelItem.id,
      labelItemName: labelItem.name,
      labelQtyUsed: labelQty,
      labelCostOMR: calc['labelCost']!,
      factoryTollFeeOMR: tollFee,
      transportAndOtherCostOMR: transport,
      finishedItemId: finItem.id,
      finishedItemName: finItem.name,
      finishedUnit: finItem.unit,
      finishedQtyProduced: finQty,
      finishedTotalWeightKg: calc['totalFinWeightKg']!,
      wastageKg: calc['wastageKg']!,
      totalBatchCostOMR: calc['totalBatchCost']!,
      unitCostOMR: calc['unitCost']!,
      costPerKgOMR: calc['costPerKg']!,
      note: _prodNoteCtrl.text.trim(),
    );

    setState(() {
      rawItem.currentQty -= rawQty;
      cartonItem.currentQty -= cartonQty;
      nylonItem.currentQty -= nylonQty;
      labelItem.currentQty -= labelQty;

      final oldFinVal = (finItem.currentQty > 0 ? finItem.currentQty : 0.0) * finItem.avgUnitCostOMR;
      final newFinQty = (finItem.currentQty > 0 ? finItem.currentQty : 0.0) + finQty;
      if (newFinQty > 0) {
        finItem.avgUnitCostOMR = (oldFinVal + doc.totalBatchCostOMR) / newFinQty;
      }
      finItem.currentQty += finQty;
      _productions.insert(0, doc);

      _prodRawQtyCtrl.clear();
      _prodFinQtyCtrl.clear();
      _prodCartonQtyCtrl.clear();
      _prodNylonQtyCtrl.clear();
      _prodLabelQtyCtrl.clear();
      _prodTollFeeCtrl.text = '0';
      _prodTransportCtrl.text = '0';
      _warehouseSubTab = 0;
    });
    _saveLocalData();
    _pushToCloud();
    _showMsg(
      '✅ تولید ثبت شد! بهای تمام‌شده هر ${finItem.unit}: ${_fmtOMR(doc.unitCostOMR)} OMR (هر کیلو: ${_fmtOMR(doc.costPerKgOMR)} OMR)',
    );
  }

  Widget _buildThreeWarehousesAndBomTab() {
    final targetList = _inboundWhTarget == WarehouseType.rawMaterial ? _rawList : _pkgList;
    final liveCost = _previewLiveBatchCost();

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        if (_isMasterAdmin)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('📦 موجودی ۳ انبار')),
                ButtonSegment(value: 1, label: Text('📥 ورود به انبار ۱ و ۲')),
                ButtonSegment(value: 2, label: Text('⚙️ تولید و بهای تمام‌شده')),
              ],
              selected: {_warehouseSubTab},
              onSelectionChanged: (s) => setState(() => _warehouseSubTab = s.first),
            ),
          ),

        if (_warehouseSubTab == 0 || !_isMasterAdmin) ...[
          _buildWarehouseCard('🧱 انبار ۱: مواد اولیه اصلی (پنیر بلوکی، کره فله و...)', const Color(0xFF0369A1),
              WarehouseType.rawMaterial, _rawList),
          const SizedBox(height: 12),
          _buildWarehouseCard('📦 انبار ۲: ملزومات بسته‌بندی (کارتن، نایلون، لیبل و...)', const Color(0xFFB45309),
              WarehouseType.packagingSupply, _pkgList),
          const SizedBox(height: 12),
          _buildWarehouseCard('🏷️ انبار ۳: محصولات نهایی آماده فروش (دارای بهای تمام‌شده)', const Color(0xFF0F766E),
              WarehouseType.finishedGood, _finList),
        ] else if (_warehouseSubTab == 1) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<WarehouseType>(
                    segments: const [
                      ButtonSegment(value: WarehouseType.rawMaterial, label: Text('🧱 انبار ۱ (مواد اولیه)')),
                      ButtonSegment(value: WarehouseType.packagingSupply, label: Text('📦 انبار ۲ (کارتن/نایلون/لیبل)')),
                    ],
                    selected: {_inboundWhTarget},
                    onSelectionChanged: (s) {
                      setState(() {
                        _inboundWhTarget = s.first;
                        _syncDefaults();
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedInboundItemId,
                    items: targetList.map((i) => DropdownMenuItem(value: i.id, child: Text(i.name))).toList(),
                    onChanged: (v) => setState(() => _selectedInboundItemId = v),
                    decoration: const InputDecoration(labelText: 'انتخاب کالا / ملزومات ورودی', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _inbQtyCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'مقدار / تعداد ورودی *', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _inbPriceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'قیمت خرید واحد (OMR) *', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _inbFreightCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'هزینه حمل/گمرک کل بار (OMR)', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _savePurchaseInbound,
                    child: const Text('ثبت ورود و محاسبه میانگین موزون بهای تمام‌شده'),
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('⚙️ ثبت تولید کارمزدی و محاسبه بهای تمام‌شده صنعتی (کسر از انبار ۱ و ۲ -> شارژ انبار ۳):',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          value: _prodRawId,
                          items: _rawList.map((r) => DropdownMenuItem(value: r.id, child: Text(r.name))).toList(),
                          onChanged: (v) => setState(() => _prodRawId = v),
                          decoration: const InputDecoration(labelText: '۱. ماده اولیه مصرفی از انبار ۱', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _prodRawQtyCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(labelText: 'مقدار مصرفی (کیلو)', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          value: _prodFinId,
                          items: _finList.map((f) => DropdownMenuItem(value: f.id, child: Text(f.name))).toList(),
                          onChanged: (v) {
                            setState(() {
                              _prodFinId = v;
                              _autoCalcBom(_prodFinQtyCtrl.text);
                            });
                          },
                          decoration: const InputDecoration(labelText: '۲. محصول نهایی تولیدشده (انبار ۳)', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _prodFinQtyCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (v) => _autoCalcBom(v),
                          decoration: const InputDecoration(labelText: 'تعداد بسته تولیدی', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _prodCartonQtyCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(labelText: 'کارتن مصرفی (انبار ۲)', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _prodNylonQtyCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(labelText: 'نایلون مصرفی (انبار ۲)', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _prodLabelQtyCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(labelText: 'لیبل مصرفی (انبار ۲)', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _prodTollFeeCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(labelText: 'کارمزد کارخانه (OMR)', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _prodTransportCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(labelText: 'هزینه حمل تولید (OMR)', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDFA),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '📊 کل بهای تمام‌شده پارت: ${_fmtOMR(liveCost['totalBatchCost']!)} OMR
'
                      '🏷️ بهای تمام‌شده هر بسته: ${_fmtOMR(liveCost['unitCost']!)} OMR | هر ۱ کیلوگرم: ${_fmtOMR(liveCost['costPerKg']!)} OMR | افت: ${_fmtQty(liveCost['wastageKg']!)} کیلو',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _saveProductionBatch,
                    child: const Text('ثبت سند تولید و بهای تمام‌شده محصول'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWarehouseCard(
    String title,
    Color color,
    WarehouseType whType,
    List<InventoryItem> list,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
            const Divider(),
            ...list.map((item) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    'بهای تمام‌شده واحد: ${_fmtOMR(item.avgUnitCostOMR)} OMR'
                    '${whType == WarehouseType.finishedGood ? ' | قیمت فروش: ${_fmtOMR(item.defaultSalePriceOMR)} OMR' : ''}',
                  ),
                  trailing: Text(
                    'موجودی: ${_fmtQty(item.currentQty)} ${item.unit}',
                    style: TextStyle(fontWeight: FontWeight.bold, color: color),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // تب ۳: فروش به مشتریان، محاسبه زنده سود/زیان و تقسیم سود بین شرکا
  // ==========================================================================
  void _saveSaleInvoice() {
    if (!_isMasterAdmin) return;
    final qty = double.tryParse(_saleQtyCtrl.text.trim()) ?? 0.0;
    final price = double.tryParse(_salePriceCtrl.text.trim()) ?? 0.0;
    final deliv = double.tryParse(_saleDeliveryCostCtrl.text.trim()) ?? 0.0;
    final divisor = _salePartnerDivisor == 0
        ? (int.tryParse(_customDivisorCtrl.text.trim()) ?? 1)
        : _salePartnerDivisor;

    if (_saleFinId == null || qty <= 0 || price < 0) {
      _showMsg('لطفاً محصول، تعداد فروش و قیمت واحد را وارد کنید.');
      return;
    }

    final finItem = _items.firstWhere((e) => e.id == _saleFinId!);
    final doc = SaleProfitDoc(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: DateTime.now(),
      finishedItemId: finItem.id,
      finishedItemName: finItem.name,
      unit: finItem.unit,
      qtySold: qty,
      unitSalePriceOMR: price,
      unitCogsOMR: finItem.avgUnitCostOMR,
      deliveryExpenseOMR: deliv,
      customerName: _saleCustomer ?? 'مشتری بازار عمان',
      paymentStatus: _salePaymentStatus,
      partnerSplitDivisor: divisor < 1 ? 1 : divisor,
      note: _saleNoteCtrl.text.trim(),
    );

    setState(() {
      finItem.currentQty -= qty;
      _sales.insert(0, doc);
      _saleQtyCtrl.clear();
      _saleDeliveryCostCtrl.text = '0';
      _saleNoteCtrl.clear();
    });
    _saveLocalData();
    _pushToCloud();
    _showMsg(
      doc.isInLoss
          ? '⚠️ فروش با زیان (${_fmtOMR(doc.netProfitOrLossOMR)} OMR) ثبت شد!'
          : '✅ فروش با سود خالص +${_fmtOMR(doc.netProfitOrLossOMR)} OMR ثبت شد (سهم شما: ${_fmtOMR(doc.myProfitShareOMR)} OMR).',
    );
  }

  Widget _buildSalesProfitAndPartnerTab() {
    final finItem = _finList.firstWhere((e) => e.id == _saleFinId, orElse: () => _finList.first);
    final qty = double.tryParse(_saleQtyCtrl.text.trim()) ?? 0.0;
    final salePrice = double.tryParse(_salePriceCtrl.text.trim()) ?? 0.0;
    final delivCost = double.tryParse(_saleDeliveryCostCtrl.text.trim()) ?? 0.0;
    final divisor = _salePartnerDivisor == 0
        ? (int.tryParse(_customDivisorCtrl.text.trim()) ?? 1)
        : _salePartnerDivisor;
    final safeDivisor = divisor < 1 ? 1 : divisor;

    final totalRev = qty * salePrice;
    final totalCogs = (qty * finItem.avgUnitCostOMR) + delivCost;
    final netProfit = totalRev - totalCogs;
    final marginPct = totalRev > 0 ? (netProfit / totalRev) * 100.0 : 0.0;
    final myShare = netProfit / safeDivisor;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('🛒 ثبت فروش به مشتری، سنجش زنده حاشیه سود/زیان و تقسیم سود شریک',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _saleCustomer,
                  items: _customers.map((c) => DropdownMenuItem(value: c, child: Text('👤 $c'))).toList(),
                  onChanged: (v) => setState(() => _saleCustomer = v),
                  decoration: const InputDecoration(labelText: 'انتخاب مشتری', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _saleFinId,
                  items: _finList
                      .map((f) => DropdownMenuItem(
                            value: f.id,
                            child: Text('${f.name} (بهای تمام‌شده: ${_fmtOMR(f.avgUnitCostOMR)} OMR)'),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      _saleFinId = v;
                      final sel = _finList.firstWhere((e) => e.id == v);
                      _salePriceCtrl.text = sel.defaultSalePriceOMR.toStringAsFixed(3);
                    });
                  },
                  decoration: const InputDecoration(labelText: 'انتخاب محصول نهایی (انبار ۳)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _saleQtyCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(labelText: 'تعداد فروش *', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _salePriceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(labelText: 'فی فروش به مشتری (OMR) *', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('🤝 تقسیم سود این بار بین شما و شریک:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 1, label: Text('۱۰۰٪ خودم')),
                    ButtonSegment(value: 2, label: Text('تقسیم بر ۲')),
                    ButtonSegment(value: 3, label: Text('تقسیم بر ۳')),
                    ButtonSegment(value: 0, label: Text('عدد دلخواه')),
                  ],
                  selected: {_salePartnerDivisor},
                  onSelectionChanged: (s) => setState(() => _salePartnerDivisor = s.first),
                ),
                if (_salePartnerDivisor == 0) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _customDivisorCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'تقسیم بر چند نفر؟', border: OutlineInputBorder()),
                  ),
                ],
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: netProfit >= 0 ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${netProfit >= 0 ? '✅ در سود' : '⚠️ هشدار فروش در زیان!'} | حاشیه سود: ${marginPct.toStringAsFixed(1)}%
'
                    'فروش کل: ${_fmtOMR(totalRev)} OMR | بهای تمام‌شده کل: ${_fmtOMR(totalCogs)} OMR
'
                    'سود/زیان خالص: ${_fmtOMR(netProfit)} OMR  |  👤 سهم شما (÷$safeDivisor): ${_fmtOMR(myShare)} OMR',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _saveSaleInvoice,
                  child: const Text('ثبت فاکتور فروش و کسر از انبار محصول'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // تب ۴: گزارش‌گیری یکپارچه (هم گزارش تجمیعی/ریز تنخواه و هم صورت سود و زیان انبار و شرکا)
  // ==========================================================================
  Widget _buildUnifiedReportsAndCfoTab() {
    // تجمیع عناوین تکراری تنخواه (مثلاً ۶ بار بنزین در یک ردیف)
    final Map<String, ConsolidatedExpenseRow> byTitle = {};
    for (final t in _transactions) {
      final k = '${t.title.trim()}__${t.category}';
      final row = byTitle.putIfAbsent(
        k,
        () => ConsolidatedExpenseRow(
          groupTitle: t.title.trim(),
          subTitle: t.category,
          count: 0,
          totalExpenseOMR: 0,
          totalDepositOMR: 0,
          firstDate: t.date,
          lastDate: t.date,
        ),
      );
      row.count++;
      if (t.mode == TxMode.deposit) {
        row.totalDepositOMR += t.amountOMR;
      } else {
        row.totalExpenseOMR += t.amountOMR;
      }
    }

    double sumRev = 0;
    double sumCogs = 0;
    double sumProfit = 0;
    double sumMyShare = 0;
    double sumPartnerShare = 0;
    for (final s in _sales) {
      sumRev += s.totalRevenueOMR;
      sumCogs += s.totalCogsOMR;
      sumProfit += s.netProfitOrLossOMR;
      sumMyShare += s.myProfitShareOMR;
      sumPartnerShare += s.partnersProfitShareOMR;
    }

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('📑 ۱. گزارش تجمیعی و ریز تنخواه و هزینه‌ها')),
            ButtonSegment(value: 1, label: Text('🏦 ۲. صورت سود و زیان، بهای تمام‌شده و سهم شریک')),
          ],
          selected: {_reportSectionTab},
          onSelectionChanged: (s) => setState(() => _reportSectionTab = s.first),
        ),
        const SizedBox(height: 12),

        if (_reportSectionTab == 0)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📑 گزارش تجمیعی تنخواه و هزینه‌های روزانه (جمع موارد مشابه در یک ردیف واحد):',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                  const Divider(),
                  if (byTitle.isEmpty)
                    const Text('هنوز هزینه‌ای ثبت نشده است.')
                  else
                    ...byTitle.values.map((r) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${r.groupTitle} (${r.count} نوبت تجمیع‌شده)',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('سرفصل: ${r.subTitle}'),
                          trailing: Text(
                            '${_fmtOMR(r.totalExpenseOMR > 0 ? r.totalExpenseOMR : r.totalDepositOMR)} OMR',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        )),
                ],
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🏦 صورت سود و زیان استاندارد (P&L)، بهای تمام‌شده و تسهیم سود شرکا:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: Color(0xFF0F766E))),
                  const Divider(),
                  Text('• کل درآمد فروش محصولات: ${_fmtOMR(sumRev)} OMR'),
                  Text('• منهای: کل بهای تمام‌شده کالای فروش‌رفته (COGS): (${_fmtOMR(sumCogs)} OMR)'),
                  Text(
                    '💵 سود (یا زیان) خالص کل: ${_fmtOMR(sumProfit)} OMR',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '👤 جمع سهم خالص شما: ${_fmtOMR(sumMyShare)} OMR  |  🤝 جمع سهم شریک/شرکا: ${_fmtOMR(sumPartnerShare)} OMR',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0369A1)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ==========================================================================
  // تب ۵: مدیریت سرفصل‌ها، موضوعات، مشتریان و افزودن کالاهای جدید به ۳ انبار
  // ==========================================================================
  Widget _buildCustomizeSettingsTab() {
    final newCatCtrl = TextEditingController();
    final newCustCtrl = TextEditingController();

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('👤 افزودن مشتری جدید به دفتر مشتریان:', style: TextStyle(fontWeight: FontWeight.bold)),
                TextField(controller: newCustCtrl, decoration: const InputDecoration(labelText: 'نام مشتری / فروشگاه')),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () {
                    final v = newCustCtrl.text.trim();
                    if (v.isNotEmpty && !_customers.contains(v)) {
                      setState(() => _customers.add(v));
                      _saveLocalData();
                      _pushToCloud();
                    }
                  },
                  child: const Text('+ افزودن مشتری'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('📂 افزودن سرفصل هزینه جدید به تنخواه:', style: TextStyle(fontWeight: FontWeight.bold)),
                TextField(controller: newCatCtrl, decoration: const InputDecoration(labelText: 'نام سرفصل جدید')),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () {
                    final v = newCatCtrl.text.trim();
                    if (v.isNotEmpty && !_categories.contains(v)) {
                      setState(() => _categories.add(v));
                      _saveLocalData();
                      _pushToCloud();
                    }
                  },
                  child: const Text('+ افزودن سرفصل'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
