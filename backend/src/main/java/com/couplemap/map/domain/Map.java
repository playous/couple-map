package com.couplemap.map.domain;

import com.couplemap.global.common.BaseEntity;
import jakarta.persistence.*;
import lombok.*;


@Entity
@Getter
@Builder(access = AccessLevel.PRIVATE)
@AllArgsConstructor
@Table(name = "maps")
@NoArgsConstructor
public class Map extends BaseEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "map_id")
    private Long mapId;

    @Column(name = "map_name", nullable = false, length = 20)
    private String mapName;

    @Column(name = "description", length = 20)
    private String description;

    // 접근, 삭제 모두 이 키로 한다. URL은 조회 시점에 서명해서 만들고 저장하지 않는다
    @Column(name = "background_key")
    private String backgroundKey;

    @Column(name = "category", nullable = false)
    private String category;

    public static Map from(String mapName, String description, String category) {
        return Map.builder()
                .mapName(mapName)
                .description(description)
                .category(category)
                .build();
    }

    public void update(String mapName, String description, String category) {
        this.mapName = mapName;
        this.description = description;
        this.category = category;
    }

    public void updateBackgroundKey(String backgroundKey) {
        this.backgroundKey = backgroundKey;
    }

    public void deleteBackground() {
        this.backgroundKey = null;
    }
}
