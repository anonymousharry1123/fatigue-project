import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The current page's vertical content, excluding tab pagers and charts.
Finder activeVerticalScrollable() => find
    .byWidgetPredicate(
      (widget) =>
          widget is Scrollable &&
          (widget.axisDirection == AxisDirection.down ||
              widget.axisDirection == AxisDirection.up),
      description: 'vertical page scrollable',
    )
    .hitTestable()
    .first;
