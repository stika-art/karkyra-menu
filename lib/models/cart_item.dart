class CartItem {
  final String id;
  final String menuItemId;
  final int quantity;
  final String tableId;
  final String addedBy;
  final DateTime createdAt;
  final String status; // 'ordering', 'confirmed'

  CartItem({
    required this.id,
    required this.menuItemId,
    required this.quantity,
    required this.tableId,
    required this.addedBy,
    required this.createdAt,
    this.status = 'ordering',
  });

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      id: json['id'],
      menuItemId: json['menu_item_id'],
      quantity: json['quantity'] ?? 1,
      tableId: json['table_id'],
      addedBy: json['added_by'] ?? 'unknown',
      createdAt: DateTime.parse(json['created_at']),
      status: json['status'] ?? 'ordering',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'menu_item_id': menuItemId,
      'quantity': quantity,
      'table_id': tableId,
      'added_by': addedBy,
      'status': status,
    };
  }
}
