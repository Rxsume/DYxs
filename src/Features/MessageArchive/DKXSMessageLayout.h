//  DKXSMessageLayout.h
//  DY778 第 1 批 staging：时间 / 撤回 / 编辑三枚标记在气泡旁的避让布局。
//  由上游 DY778MessageLayout.h 改名前缀而来，算法一字未改：
//  同位置的多枚标记先成组再找列；空间不足时状态标记优先，时间标签让位；
//  实在放不下时状态标记退回气泡内绘制区，绝不画到行外。
//  纯 C，不依赖任何抖音类。

#ifndef DKXSMessageLayout_h
#define DKXSMessageLayout_h

#include <math.h>
#include <stddef.h>

typedef struct { double x, y, width, height; } DKXSLayoutRect;
typedef enum { DKXSLayoutRight, DKXSLayoutAbove, DKXSLayoutBelow, DKXSLayoutLeft } DKXSLayoutPosition;
typedef struct { double width, height; int visible; DKXSLayoutPosition position; } DKXSLayoutItem;
typedef struct { DKXSLayoutRect time, recall; int timeVisible, recallVisible; DKXSLayoutPosition timePosition, recallPosition; } DKXSMessageLayoutResult;

static inline double DKXSLayoutMax(double a, double b) { return a > b ? a : b; }
static inline double DKXSLayoutMin(double a, double b) { return a < b ? a : b; }
static inline int DKXSLayoutIntersects(DKXSLayoutRect a, DKXSLayoutRect b) {
    return a.width > 0 && a.height > 0 && b.width > 0 && b.height > 0 &&
        a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;
}
static inline int DKXSLayoutFits(DKXSLayoutRect r, DKXSLayoutRect bounds, const DKXSLayoutRect *obstacles, size_t count) {
    if (!isfinite(r.x + r.y + r.width + r.height + bounds.x + bounds.y + bounds.width + bounds.height) || bounds.width <= 0 || bounds.height <= 0 || r.width <= 0 || r.height <= 0 ||
        r.x < bounds.x + 4 || r.y < bounds.y + 2 ||
        r.x + r.width > bounds.x + bounds.width - 4 || r.y + r.height > bounds.y + bounds.height - 2) return 0;
    for (size_t i = 0; i < count; i++) if (DKXSLayoutIntersects(r, obstacles[i])) return 0;
    return 1;
}
static inline DKXSLayoutRect DKXSLayoutCandidate(DKXSLayoutRect bubble, double width, double height, DKXSLayoutPosition position, int outgoing) {
    const double gap = 5;
    DKXSLayoutRect r = {bubble.x, bubble.y, width, height};
    if (position == DKXSLayoutRight) { r.x = bubble.x + bubble.width + gap; r.y = bubble.y + (bubble.height - height) / 2; }
    else { r.x = outgoing ? bubble.x + bubble.width - width : bubble.x; r.y = position == DKXSLayoutAbove ? bubble.y - height - 3 : bubble.y + bubble.height + 3; }
    return r;
}
static inline int DKXSLayoutRightColumn(DKXSLayoutRect bounds, DKXSLayoutRect candidate,
    const DKXSLayoutRect *obstacles, size_t count, DKXSLayoutRect *result) {
    double minY = bounds.y + 2, maxY = bounds.y + bounds.height - candidate.height - 2;
    if (maxY < minY) return 0;
    candidate.y = DKXSLayoutMax(minY, DKXSLayoutMin(maxY, candidate.y));
    if (DKXSLayoutFits(candidate, bounds, obstacles, count)) { *result = candidate; return 1; }
    double nearest = INFINITY;
    // 整列绕开已有标签平移；x 永不越过气泡。
    for (size_t i = 0; i < count; i++) {
        if (candidate.x >= obstacles[i].x + obstacles[i].width || candidate.x + candidate.width <= obstacles[i].x) continue;
        double edges[2] = {obstacles[i].y - candidate.height - 2, obstacles[i].y + obstacles[i].height + 2};
        for (size_t edge = 0; edge < 2; edge++) {
            DKXSLayoutRect shifted = candidate; shifted.y = edges[edge];
            double distance = fabs(shifted.y - candidate.y);
            if (distance < nearest && DKXSLayoutFits(shifted, bounds, obstacles, count)) { *result = shifted; nearest = distance; }
        }
    }
    return isfinite(nearest);
}
static inline int DKXSLayoutRightPlace(DKXSLayoutRect bounds, DKXSLayoutRect candidate,
    const DKXSLayoutRect *obstacles, size_t count, DKXSLayoutRect *result) {
    if (DKXSLayoutRightColumn(bounds, candidate, obstacles, count, result)) return 1;
    // 另一插件可能已占最近一列：把本组标记放一起，再试右侧有限列。
    double columns[8]; size_t columnsCount = 0;
    for (size_t i = 0; i < count; i++) {
        double x = obstacles[i].x + obstacles[i].width + 3;
        if (!isfinite(x) || x <= candidate.x || x + candidate.width > bounds.x + bounds.width - 4) continue;
        size_t position = 0;
        while (position < columnsCount && columns[position] < x) position++;
        if (position < columnsCount && columns[position] == x) continue;
        if (position >= 8) continue;
        if (columnsCount < 8) columnsCount++;
        for (size_t j = columnsCount - 1; j > position; j--) columns[j] = columns[j - 1];
        columns[position] = x;
    }
    for (size_t i = 0; i < columnsCount; i++) {
        DKXSLayoutRect shifted = candidate; shifted.x = columns[i];
        if (DKXSLayoutRightColumn(bounds, shifted, obstacles, count, result)) return 1;
    }
    return 0;
}
static inline int DKXSLayoutPlace(DKXSLayoutRect bounds, DKXSLayoutRect bubble, DKXSLayoutItem item, int outgoing,
    const DKXSLayoutRect *obstacles, size_t count, DKXSLayoutRect *result, DKXSLayoutPosition *resolved) {
    if (!isfinite(item.width + item.height) || item.width <= 0 || item.height <= 0) return 0;
    DKXSLayoutPosition order[3] = {DKXSLayoutRight, DKXSLayoutBelow, DKXSLayoutAbove};
    if (item.position == DKXSLayoutBelow || item.position == DKXSLayoutAbove) order[0] = item.position;
    if (item.position == DKXSLayoutBelow) { order[1] = DKXSLayoutRight; order[2] = DKXSLayoutAbove; }
    if (item.position == DKXSLayoutAbove) { order[1] = DKXSLayoutBelow; order[2] = DKXSLayoutRight; }
    for (size_t p = 0; p < 3; p++) {
        DKXSLayoutRect r = DKXSLayoutCandidate(bubble, item.width, item.height, order[p], outgoing);
        if (order[p] == DKXSLayoutRight) {
            if (DKXSLayoutRightPlace(bounds, r, obstacles, count, result)) { *resolved = DKXSLayoutRight; return 1; }
            continue;
        }
        if (DKXSLayoutFits(r, bounds, obstacles, count)) { *result = r; *resolved = order[p]; return 1; }
    }
    return 0;
}
// 三枚独立装饰；状态标记优先于时间标签。
typedef struct { DKXSLayoutRect frames[3]; int visible[3]; DKXSLayoutPosition positions[3]; int statusFallback; } DKXSDecorationLayoutResult;
static inline DKXSDecorationLayoutResult DKXSPlaceDecorations(DKXSLayoutRect bounds, DKXSLayoutRect bubble,
    const DKXSLayoutItem items[3], int outgoing, const DKXSLayoutRect *obstacles, size_t count) {
    DKXSDecorationLayoutResult result = {0};
    if (count > 128 || (count && !obstacles) || !isfinite(bubble.x + bubble.y + bubble.width + bubble.height) || bubble.width <= 0 || bubble.height <= 0) return result;
    DKXSLayoutRect occupied[132]; size_t used = 0;
    for (size_t i = 0; i < count; i++) occupied[used++] = obstacles[i];
    occupied[used++] = bubble;
    int processed[3] = {0}, order[3] = {1, 2, 0};
    for (int priority = 0; priority < 3; priority++) {
        int first = order[priority]; if (processed[first] || !items[first].visible) continue;
        DKXSLayoutItem group = {0, 0, 1, items[first].position}; int members[3], total = 0;
        for (int i = 0; i < 3; i++) if (!processed[i] && items[i].visible && items[i].position == group.position) {
            processed[i] = 1; members[total++] = i;
            group.width = DKXSLayoutMax(group.width, items[i].width); group.height += items[i].height + (total > 1 ? 2 : 0);
        }
        DKXSLayoutRect frame; DKXSLayoutPosition position;
        if (!DKXSLayoutPlace(bounds, bubble, group, outgoing, occupied, used, &frame, &position)) continue;
        double y = frame.y;
        for (int n = 0; n < total; n++) {
            int i = members[n]; result.frames[i] = (DKXSLayoutRect){frame.x, y, items[i].width, items[i].height};
            result.visible[i] = 1; result.positions[i] = position; y += items[i].height + 2;
        }
        occupied[used++] = frame;
    }
    return result;
}
// 最后一招：状态标记画进消息已绘区域，绝不出行。
static inline DKXSLayoutRect DKXSStatusFallbackRect(DKXSLayoutRect bounds, DKXSLayoutRect bubble, double width, double height) {
    DKXSLayoutRect empty = {0};
    if (!isfinite(bounds.x + bounds.y + bounds.width + bounds.height + bubble.x + bubble.y + bubble.width + width + height) || bounds.width < 24 || bounds.height < 16 || width <= 0 || height <= 0) return empty;
    width = DKXSLayoutMin(width, bounds.width - 8); height = DKXSLayoutMin(height, bounds.height - 4);
    return (DKXSLayoutRect){DKXSLayoutMax(bounds.x + 4, DKXSLayoutMin(bubble.x + bubble.width - width, bounds.x + bounds.width - width - 4)),
        DKXSLayoutMax(bounds.y + 2, DKXSLayoutMin(bubble.y + 2, bounds.y + bounds.height - height - 2)), width, height};
}
static inline DKXSDecorationLayoutResult DKXSComputeDecorationLayout(DKXSLayoutRect bounds, DKXSLayoutRect bubble,
    DKXSLayoutItem time, DKXSLayoutItem recall, DKXSLayoutItem edit, int outgoing, const DKXSLayoutRect *obstacles, size_t count) {
    DKXSLayoutItem items[3] = {time, recall, edit};
    DKXSDecorationLayoutResult result = {0};
    if (count > 128 || (count && !obstacles)) return result;
    result = DKXSPlaceDecorations(bounds, bubble, items, outgoing, obstacles, count);
    if ((recall.visible && !result.visible[1]) || (edit.visible && !result.visible[2])) {
        items[0].visible = 0;
        result = DKXSPlaceDecorations(bounds, bubble, items, outgoing, obstacles, count);
    }
    if ((recall.visible && !result.visible[1]) || (edit.visible && !result.visible[2])) {
        // 短行空间耗尽时仍要让状态标记可读：同行横排或退回气泡内。
        int both = recall.visible && edit.visible;
        int horizontal = both && recall.height + edit.height + 2 > bounds.height - 4;
        double width = both ? (horizontal ? recall.width + edit.width + 4 : DKXSLayoutMax(recall.width, edit.width)) : (recall.visible ? recall.width : edit.width);
        double height = both ? (horizontal ? DKXSLayoutMax(recall.height, edit.height) : recall.height + edit.height + 2) : (recall.visible ? recall.height : edit.height);
        DKXSLayoutRect frame = DKXSStatusFallbackRect(bounds, bubble, width, height);
        result.visible[0] = result.visible[1] = result.visible[2] = 0;
        result.statusFallback = 1;
        if (frame.width <= 0 || frame.height <= 0) return result;
        if (!both) { int i = recall.visible ? 1 : 2; result.frames[i] = frame; result.visible[i] = 1; }
        else if (horizontal) {
            double firstWidth = DKXSLayoutMin(recall.width, (frame.width - 4) * .5);
            result.frames[1] = (DKXSLayoutRect){frame.x, frame.y, firstWidth, frame.height};
            result.frames[2] = (DKXSLayoutRect){frame.x + firstWidth + 4, frame.y, frame.width - firstWidth - 4, frame.height};
            result.visible[1] = result.visible[2] = 1;
        } else {
            result.frames[1] = (DKXSLayoutRect){frame.x, frame.y, frame.width, recall.height};
            result.frames[2] = (DKXSLayoutRect){frame.x, frame.y + recall.height + 2, frame.width, edit.height};
            result.visible[1] = result.visible[2] = 1;
        }
    }
    return result;
}

#endif
